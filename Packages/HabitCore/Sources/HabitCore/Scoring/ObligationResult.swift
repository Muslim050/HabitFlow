import Foundation

/// One judged obligation: a day the schedule named, or a week/month with its quota.
/// Scoring counts these rather than days, because "three times a week" makes no claim about
/// any particular day — only the week can be said to have been kept or missed.
public struct ObligationResult: Sendable, Equatable {
    public var start: DayKey
    /// Inclusive.
    public var end: DayKey
    public var period: SchedulePeriod
    public var required: Int
    public var done: Int
    /// Best partial progress inside the obligation, 0…1. For a single day, that day's ratio.
    public var partial: Double
    /// Still running, so it cannot be called a miss yet.
    public var isOpen: Bool

    public init(start: DayKey, end: DayKey, period: SchedulePeriod,
                required: Int, done: Int, partial: Double, isOpen: Bool) {
        self.start = start
        self.end = end
        self.period = period
        self.required = required
        self.done = done
        self.partial = partial
        self.isOpen = isOpen
    }

    public var fulfilled: Bool { done >= required }

    /// 0…1 credit for the consistency index. A single day keeps the original rule — full credit
    /// when done, half credit scaled by how close the ring got. A quota counts how much of it
    /// was met, never quite reaching 1 unless it actually was.
    public var credit: Double {
        if fulfilled { return 1 }
        if required > 1 { return min(Double(done) / Double(required), 0.99) }
        return min(partial, 0.99) * 0.5
    }
}

public enum ObligationResultBuilder {
    /// Ascending obligations from the habit's creation day (or `from`) through the one containing
    /// `today`. Days after `today` never count as done, so the current week is judged on what has
    /// happened so far and marked open.
    public static func build(habit: Habit, logs: [DailyLog], calendar: DayCalendar,
                             today: DayKey, from: DayKey? = nil) -> [ObligationResult] {
        let resolver = ScheduleResolver(habit: habit, calendar: calendar)
        let firstKey = from ?? calendar.dayKey(for: habit.createdAt)
        let byKey = Dictionary(logs.map { ($0.dayKey, $0) }, uniquingKeysWith: { a, b in a.updatedAt >= b.updatedAt ? a : b })

        return resolver.obligations(from: firstKey, to: today).map { obligation in
            var done = 0
            var partial = 0.0
            for key in calendar.keys(from: obligation.start, to: min(obligation.end, today)) {
                guard let log = byKey[key.raw] else { continue }
                if log.isCompleted { done += 1 }
                partial = max(partial, log.ratio)
            }
            return ObligationResult(
                start: obligation.start, end: obligation.end, period: obligation.period,
                required: obligation.quota, done: done, partial: partial,
                isOpen: obligation.end >= today
            )
        }
    }
}
