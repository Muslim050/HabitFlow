import Foundation
import Observation
import SwiftData
import UIKit
import WidgetKit
import HabitCore

/// Composition root. Owns the store, providers, engine and the foreground timer.
@MainActor
@Observable
final class AppEnvironment {
    static let shared = AppEnvironment()

    let container: ModelContainer
    let repository: SwiftDataHabitRepository
    let settings: AppSettings
    let registry: ProviderRegistry
    let healthKit: HealthKitProvider
    let location: LocationProvider
    let notifications: NotificationService
    let engine: AutoTrackingEngine
    let analysis: AnalysisService
    let isUsingFallbackStore: Bool

    /// Bumps after every engine run so views can refresh derived data.
    private(set) var evaluationTick = 0
    private(set) var lastSummary: EvaluationSummary?
    private(set) var currentDayKey: DayKey
    private(set) var pendingDeepLink: URL?

    @ObservationIgnored private var foregroundTimer: Timer?

    private init() {
        let settings = AppSettings.shared
        var fallback = false
        let container: ModelContainer
        do {
            container = try ModelContainerFactory.shared()
        } catch {
            Log.app.error("Shared store unavailable (\(error.localizedDescription)); using in-memory store")
            // swiftlint:disable:next force_try
            container = try! ModelContainerFactory.inMemory()
            fallback = true
        }
        self.container = container
        self.isUsingFallbackStore = fallback
        self.settings = settings
        self.repository = SwiftDataHabitRepository(container: container)
        self.registry = ProviderRegistry()
        self.healthKit = HealthKitProvider()
        self.location = LocationProvider(repository: repository)
        self.notifications = NotificationService()
        self.currentDayKey = settings.dayCalendar.today()
        registry.register(healthKit)
        registry.register(location)
        self.engine = AutoTrackingEngine(repository: repository, providers: registry, settings: settings)
        self.analysis = AnalysisService(repository: repository, settings: settings)

        engine.onAutoCompleted = { [weak self] event in
            self?.handleAutoCompleted(event)
        }
        engine.onDidEvaluate = { [weak self] summary in
            self?.handleDidEvaluate(summary)
        }
    }

    // MARK: Lifecycle

    func handleLaunch(launchedForLocation: Bool) {
        Log.app.info("Launch (location wake: \(launchedForLocation))")
        location.restoreMonitoring()
        refreshObservers()
        if launchedForLocation {
            Task { await engine.evaluate(kinds: [.geofence], reason: .locationEvent) }
        }
    }

    func startForegroundSession() {
        Task {
            await reconcileDayRollover()
            replayWidgetActions()
            await engine.evaluateAll(reason: .foreground)
        }
        foregroundTimer?.invalidate()
        foregroundTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                await self.reconcileDayRollover()
                await self.engine.evaluateAll(reason: .timer)
            }
        }
    }

    func endForegroundSession() {
        foregroundTimer?.invalidate()
        foregroundTimer = nil
        BackgroundRefresh.schedule(earliest: nextRefreshDate())
    }

    /// If the logical day changed since the last check, finalize the old day and evaluate the new one.
    func reconcileDayRollover() async {
        let today = settings.dayCalendar.today()
        guard today != currentDayKey else { return }
        let previous = currentDayKey
        currentDayKey = today
        await engine.finalizeDay(previous)
        await engine.evaluateAll(reason: .dayRollover)
        analysis.refreshIfNeeded(force: true)
    }

    private func nextRefreshDate() -> Date {
        let calendar = settings.dayCalendar
        let tomorrowStart = calendar.dayStart(for: calendar.key(byAdding: 1, to: calendar.today()))
        return min(Date().addingTimeInterval(4 * 3600), tomorrowStart.addingTimeInterval(-30 * 60))
    }

    // MARK: Habits changed

    /// Call after creating/editing/archiving a habit: (re)request permissions, re-register observers, evaluate.
    func habitDidChange(_ habit: Habit?) {
        Task {
            if let habit, habit.isAutomatic, let provider = registry.provider(for: habit.kind) {
                do { try await provider.requestAuthorization(for: [habit.rule]) } catch {
                    Log.app.error("Authorization failed: \(error.localizedDescription)")
                }
            }
            refreshObservers()
            if let habit {
                await engine.evaluate(habitIDs: [habit.id], reason: .habitChanged)
            } else {
                await engine.evaluateAll(reason: .habitChanged)
            }
            analysis.refreshIfNeeded(force: true)
        }
    }

    func refreshObservers() {
        let habits = ((try? repository.activeHabits()) ?? []).filter(\.isAutomatic)
        for provider in registry.all {
            let mine = habits.filter { provider.supportedKinds.contains($0.kind) }.map { (id: $0.id, rule: $0.rule) }
            provider.startObserving(habits: mine) { [weak self] kind in
                guard let self else { return }
                let reason: EvaluationReason = kind == .geofence ? .locationEvent : .healthKitDelivery
                await self.engine.evaluate(kinds: [kind], reason: reason)
            }
        }
    }

    // MARK: Engine callbacks

    private func handleAutoCompleted(_ event: CompletionEvent) {
        guard UIApplication.shared.applicationState != .active else { return }
        guard let log = try? repository.log(habitID: event.habitID, dayKey: event.dayKey), log.notifiedAt == nil else { return }
        log.notifiedAt = Date()
        try? repository.save()
        Task { await notifications.sendAutoCompleted(event) }
    }

    private func handleDidEvaluate(_ summary: EvaluationSummary) {
        lastSummary = summary
        evaluationTick &+= 1
        analysis.refreshIfNeeded()
        WidgetCenter.shared.reloadTimelines(ofKind: TodayRingsWidgetKind)
        Task { await rescheduleNudge() }
    }

    private func rescheduleNudge() async {
        let today = currentDayKey
        let weekday = settings.dayCalendar.weekday(for: today)
        let habits = ((try? repository.activeHabits()) ?? []).filter { $0.isScheduled(weekday: weekday) }
        let logs = (try? repository.logs(dayKey: today)) ?? []
        let unfinished = habits.filter { habit in
            guard let log = logs.first(where: { $0.habitID == habit.id }) else { return true }
            if log.isCompleted { return false }
            return habit.isAutomatic ? log.ratio < 0.5 : true
        }
        await notifications.scheduleNudge(
            unfinished: unfinished.map { "\($0.emoji) \($0.name)" },
            hour: settings.nudgeHour,
            dayKey: today,
            enabled: settings.nudgeEnabled
        )
    }

    /// The widget extension wrote these to the shared store already; re-applying them through the app's
    /// own context guarantees in-memory objects match the store (SwiftData does not refresh them otherwise).
    func replayWidgetActions() {
        let actions = WidgetActionQueue.drain()
        guard !actions.isEmpty else { return }
        for action in actions {
            do {
                try engine.setManualCompletion(habitID: action.habitID, completed: action.completed, dayKey: action.dayKey)
            } catch {
                Log.app.error("Replaying widget action failed: \(error.localizedDescription)")
            }
        }
        Log.app.info("Replayed \(actions.count) widget action(s)")
    }

    // MARK: Deep links

    func handleDeepLink(_ url: URL) {
        pendingDeepLink = url
    }
}

let TodayRingsWidgetKind = "TodayRings"
