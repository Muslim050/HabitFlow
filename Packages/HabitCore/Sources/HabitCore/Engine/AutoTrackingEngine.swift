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

    /// Pauses in force, cached for the length of one run: a single evaluation touches every
    /// habit and the set does not change underneath it.
    private var pauseCache: [HabitPause]?

    private func pauseSpans(for habitID: UUID) -> [PauseSpan] {
        if pauseCache == nil { pauseCache = (try? repository.pauses()) ?? [] }
        return (pauseCache ?? []).spans(for: habitID)
    }

    /// Drops the cache so the next evaluation sees a pause that was just started or ended.
    public func pausesDidChange() { pauseCache = nil }

    // MARK: Public entry points

    @discardableResult
    public func evaluateAll(reason: EvaluationReason) async -> EvaluationSummary {
        pauseCache = nil
        let habits = (try? repository.activeHabits()) ?? []
        return await evaluate(habits: habits, reason: reason)
    }

    @discardableResult
    public func evaluate(habitIDs: [UUID], reason: EvaluationReason) async -> EvaluationSummary {
        pauseCache = nil
        let habits = habitIDs.compactMap { try? repository.habit(id: $0) }.filter { !$0.isArchived }
        return await evaluate(habits: habits, reason: reason)
    }

    @discardableResult
    public func evaluate(kinds: Set<HabitSourceKind>, reason: EvaluationReason) async -> EvaluationSummary {
        pauseCache = nil
        let habits = ((try? repository.activeHabits()) ?? []).filter { kinds.contains($0.kind) }
        return await evaluate(habits: habits, reason: reason)
    }

    /// Reconcile a past day: make sure scheduled habits have a log, evaluate it one last time,
    /// and close visits that were never exited.
    public func finalizeDay(_ key: DayKey) async {
        pauseCache = nil
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

    // MARK: Editing a day by hand

    /// The span of logical days the user may still edit, oldest first. Bounded by
    /// `AppSettings.backdateLimitDays` so an accidental scroll into last year cannot rewrite history.
    public func editableDayRange(now: Date? = nil) -> ClosedRange<DayKey> {
        let today = dayCalendar.dayKey(for: now ?? clock())
        let earliest = dayCalendar.key(byAdding: -settings.backdateLimitDays, to: today)
        return earliest...today
    }

    /// Whether this day of this habit accepts a hand edit. A day before the habit existed does not:
    /// `ActivityGrid` already leaves those out of `scheduled`, and writing a log there would invent history.
    public func canEdit(habit: Habit, dayKey key: DayKey, now: Date? = nil) -> Bool {
        let moment = now ?? clock()
        guard editableDayRange(now: moment).contains(key) else { return false }
        return key >= dayCalendar.dayKey(for: habit.createdAt)
    }

    /// User toggles a habit. `dayKey` defaults to today; a past day is accepted while it is inside
    /// `editableDayRange`. Manual habits get `.manual`; automatic ones become `.manualOverride`
    /// in either direction so the engine stops fighting the user for that day.
    public func setManualCompletion(habitID: UUID, completed: Bool, dayKey: DayKey? = nil) throws {
        guard let habit = try repository.habit(id: habitID) else { return }
        let now = clock()
        let key = dayKey ?? dayCalendar.dayKey(for: now)
        guard canEdit(habit: habit, dayKey: key, now: now) else { throw BackdateError.dayNotEditable(key) }
        let log = try repository.fetchOrCreateLog(
            habitID: habit.id, dayKey: key, dayStart: dayCalendar.dayStart(for: key), target: habit.rule.target
        )
        log.isCompleted = completed
        log.completedAt = completed ? completionInstant(for: key, now: now) : nil
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

    /// Writes a measured value for an automatic habit by hand — the case where Health simply has
    /// no sample (phone left at home, watch not worn). Completion follows from the day's own target,
    /// so a corrected day counts exactly like a day the engine closed itself.
    public func setManualValue(habitID: UUID, value: Double, dayKey: DayKey? = nil) throws {
        guard let habit = try repository.habit(id: habitID) else { return }
        guard habit.isAutomatic else { throw BackdateError.habitIsNotMeasured(habitID) }
        let now = clock()
        let key = dayKey ?? dayCalendar.dayKey(for: now)
        guard canEdit(habit: habit, dayKey: key, now: now) else { throw BackdateError.dayNotEditable(key) }
        let log = try repository.fetchOrCreateLog(
            habitID: habit.id, dayKey: key, dayStart: dayCalendar.dayStart(for: key), target: habit.rule.target
        )
        // The target is whatever this day was measured against, not today's — adaptive goals move.
        let target = log.targetValue > 0 ? log.targetValue : habit.rule.target
        log.progressValue = max(0, value)
        log.targetValue = target
        log.isCompleted = log.progressValue >= target
        log.completedAt = log.isCompleted ? completionInstant(for: key, now: now) : nil
        log.completionSource = .manualOverride
        log.updatedAt = now
        try repository.save()
        var summary = EvaluationSummary()
        summary.evaluatedHabitIDs = [habit.id]
        onDidEvaluate?(summary)
    }

    /// Removes a manual override so the engine owns the day again, then re-evaluates.
    /// Re-evaluation only reaches today; an older day is handed back to `finalizeDay`.
    public func clearOverride(habitID: UUID, dayKey: DayKey? = nil) async throws {
        let now = clock()
        let today = dayCalendar.dayKey(for: now)
        let key = dayKey ?? today
        guard let log = try repository.log(habitID: habitID, dayKey: key), log.completionSource == .manualOverride else { return }
        log.completionSource = .unset
        log.isCompleted = false
        log.completedAt = nil
        log.progressValue = 0
        log.updatedAt = now
        try repository.save()
        if key == today {
            await evaluate(habitIDs: [habitID], reason: .manualRefresh)
        } else if let habit = try repository.habit(id: habitID) {
            var summary = EvaluationSummary()
            await evaluate(habit: habit, dayKey: key, now: now, reason: .dayRollover, summary: &summary)
            try? repository.save()
            onDidEvaluate?(summary)
        }
    }

    /// Timestamp to stamp on a hand-closed day. Today gets the real instant; a past day gets the end
    /// of that logical day, so `completedAt` never lands outside the day it belongs to.
    private func completionInstant(for key: DayKey, now: Date) -> Date {
        let window = dayCalendar.window(for: key)
        return window.contains(now) ? now : window.end.addingTimeInterval(-1)
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
        // Any due day, including a flexible one: with a weekly quota, today may well be the day.
        // A paused day is not due, so a holiday leaves no empty logs behind to score later.
        guard habit.isDue(on: dayKey, calendar: dayCalendar, pauses: pauseSpans(for: habit.id)) else { return }
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
            SourceHealth.recordError(habit.kind, error.localizedDescription, at: now)
            return
        }
        SourceHealth.recordRead(habit.kind, value: snapshot.value, at: now)

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
