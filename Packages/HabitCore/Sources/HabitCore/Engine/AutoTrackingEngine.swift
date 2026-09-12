import Foundation

/// Evaluates every active habit's rule against its provider and writes `DailyLog`s.
/// Idempotent: re-running with the same data changes nothing and emits no new events.
@MainActor
public final class AutoTrackingEngine {
    public let repository: any HabitRepository
    public let providers: ProviderRegistry
    public let settings: AppSettings
    public var clock: () -> Date

    /// Fired for every fresh automatic completion (wire to notifications).
    public var onAutoCompleted: ((CompletionEvent) -> Void)?
    /// Fired after every run (wire to widget reload / nudge rescheduling).
    public var onDidEvaluate: ((EvaluationSummary) -> Void)?

    public init(repository: any HabitRepository, providers: ProviderRegistry, settings: AppSettings,
                clock: @escaping () -> Date = Date.init) {
        self.repository = repository
        self.providers = providers
        self.settings = settings
        self.clock = clock
    }

    public var dayCalendar: DayCalendar { settings.dayCalendar }

    // MARK: Public entry points

    @discardableResult
    public func evaluateAll(reason: EvaluationReason) async -> EvaluationSummary {
        let habits = (try? repository.activeHabits()) ?? []
        return await evaluate(habits: habits, reason: reason)
    }

    @discardableResult
    public func evaluate(habitIDs: [UUID], reason: EvaluationReason) async -> EvaluationSummary {
        let habits = habitIDs.compactMap { try? repository.habit(id: $0) }.filter { !$0.isArchived }
        return await evaluate(habits: habits, reason: reason)
    }

    @discardableResult
    public func evaluate(kinds: Set<HabitSourceKind>, reason: EvaluationReason) async -> EvaluationSummary {
        let habits = ((try? repository.activeHabits()) ?? []).filter { kinds.contains($0.kind) }
        return await evaluate(habits: habits, reason: reason)
    }

    /// Reconcile a past day: make sure scheduled habits have a log, evaluate it one last time,
    /// and close visits that were never exited.
    public func finalizeDay(_ key: DayKey) async {
        let now = clock()
        let habits = (try? repository.activeHabits()) ?? []
        var summary = EvaluationSummary()
        for habit in habits {
            await evaluate(habit: habit, dayKey: key, now: now, reason: .dayRollover, summary: &summary)
        }
        if let stale = try? repository.openVisits(enteredBefore: now.addingTimeInterval(-24 * 3600)) {
            for visit in stale {
                visit.exitedAt = visit.enteredAt.addingTimeInterval(24 * 3600)
                visit.updatedAt = now
            }
        }
        try? repository.save()
        settings.lastEngineRunAt = now
        onDidEvaluate?(summary)
    }

    /// User toggles a habit for today. Manual habits get `.manual`; automatic ones become `.manualOverride`
    /// in either direction so the engine stops fighting the user for that day.
    public func setManualCompletion(habitID: UUID, completed: Bool, dayKey: DayKey? = nil) throws {
        guard let habit = try repository.habit(id: habitID) else { return }
        let now = clock()
        let key = dayKey ?? dayCalendar.dayKey(for: now)
        let log = try repository.fetchOrCreateLog(
            habitID: habit.id, dayKey: key, dayStart: dayCalendar.dayStart(for: key), target: habit.rule.target
        )
        log.isCompleted = completed
        log.completedAt = completed ? now : nil
        if habit.isAutomatic {
            log.completionSource = .manualOverride
        } else {
            log.completionSource = completed ? .manual : .unset
            log.progressValue = completed ? 1 : 0
            log.targetValue = 1
        }
        log.updatedAt = now
        try repository.save()
        var summary = EvaluationSummary()
        summary.evaluatedHabitIDs = [habit.id]
        onDidEvaluate?(summary)
    }

    /// Removes a manual override so the engine owns the day again, then re-evaluates.
    public func clearOverride(habitID: UUID) async throws {
        let key = dayCalendar.dayKey(for: clock())
        guard let log = try repository.log(habitID: habitID, dayKey: key), log.completionSource == .manualOverride else { return }
        log.completionSource = .unset
        log.isCompleted = false
        log.completedAt = nil
        log.updatedAt = clock()
        try repository.save()
        await evaluate(habitIDs: [habitID], reason: .manualRefresh)
    }

    // MARK: Core

    private func evaluate(habits: [Habit], reason: EvaluationReason) async -> EvaluationSummary {
        let now = clock()
        let today = dayCalendar.dayKey(for: now)
        var summary = EvaluationSummary()
        for habit in habits {
            await evaluate(habit: habit, dayKey: today, now: now, reason: reason, summary: &summary)
        }
        try? repository.save()
        settings.lastEngineRunAt = now
        for event in summary.completions { onAutoCompleted?(event) }
        onDidEvaluate?(summary)
        return summary
    }

    private func evaluate(habit: Habit, dayKey: DayKey, now: Date, reason: EvaluationReason,
                          summary: inout EvaluationSummary) async {
        guard habit.isAutomatic else { return }
        guard habit.isScheduled(weekday: dayCalendar.weekday(for: dayKey)) else { return }
        guard dayCalendar.window(for: dayKey).end > habit.createdAt else { return }
        guard let provider = providers.provider(for: habit.kind) else {
            summary.failures[habit.id] = "No provider for \(habit.kind.rawValue)"
            return
        }

        let rule = habit.rule
        let window: DateInterval = (habit.kind == .healthSleep)
            ? dayCalendar.sleepWindow(for: dayKey)
            : dayCalendar.window(for: dayKey)

        let log: DailyLog
        do {
            log = try repository.fetchOrCreateLog(
                habitID: habit.id, dayKey: dayKey, dayStart: dayCalendar.dayStart(for: dayKey), target: rule.target
            )
        } catch {
            summary.failures[habit.id] = error.localizedDescription
            return
        }
        summary.evaluatedHabitIDs.append(habit.id)

        let snapshot: ProgressSnapshot
        do {
            snapshot = try await provider.snapshot(for: rule, habitID: habit.id, window: window, now: now)
        } catch {
            log.lastEvaluatedAt = now
            summary.failures[habit.id] = error.localizedDescription
            return
        }

        let progressChanged = log.progressValue != snapshot.value || log.targetValue != snapshot.target
        log.progressValue = snapshot.value
        log.targetValue = snapshot.target
        log.lastEvaluatedAt = now
        if progressChanged { log.updatedAt = now }

        // The user's explicit decision for the day wins; keep the ring live but leave completion alone.
        guard log.completionSource != .manualOverride else { return }

        if snapshot.isSatisfied && !log.isCompleted {
            log.isCompleted = true
            log.completedAt = now
            log.completionSource = .auto
            log.updatedAt = now
            summary.completions.append(CompletionEvent(
                habitID: habit.id, habitName: habit.name, emoji: habit.emoji, dayKey: dayKey,
                value: snapshot.value, target: snapshot.target, unitLabel: rule.unitLabel,
                sourceLabel: rule.sourceLabel ?? "", reason: reason
            ))
        } else if !snapshot.isSatisfied && log.isCompleted && log.completionSource == .auto {
            // Data disappeared (e.g. a workout deleted in Health). Only today can be un-completed.
            if dayKey == dayCalendar.dayKey(for: now) {
                log.isCompleted = false
                log.completedAt = nil
                log.completionSource = .unset
                log.updatedAt = now
            }
        }
    }
}
