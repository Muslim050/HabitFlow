import Foundation

/// One scheduled-or-not day in a habit's history, as seen by the scoring functions.
public struct DayResult: Sendable, Equatable {
    public var dayKey: DayKey
    public var scheduled: Bool
    public var completed: Bool
    /// Partial progress 0…1 (automatic habits only; manual habits are 0 or 1).
    public var ratio: Double

    public init(dayKey: DayKey, scheduled: Bool = true, completed: Bool, ratio: Double? = nil) {
        self.dayKey = dayKey
        self.scheduled = scheduled
        self.completed = completed
        self.ratio = ratio ?? (completed ? 1 : 0)
    }
}

public enum DayResultBuilder {
    /// Builds ascending results from the habit's creation day (or `from`) through `today`.
    /// Days without a log count as not completed.
    public static func build(habit: Habit, logs: [DailyLog], calendar: DayCalendar, today: DayKey, from: DayKey? = nil) -> [DayResult] {
        let firstKey = from ?? calendar.dayKey(for: habit.createdAt)
        let byKey = Dictionary(logs.map { ($0.dayKey, $0) }, uniquingKeysWith: { a, b in a.updatedAt >= b.updatedAt ? a : b })
        return calendar.keys(from: firstKey, to: today).map { key in
            let log = byKey[key.raw]
            return DayResult(
                dayKey: key,
                scheduled: habit.isScheduled(weekday: calendar.weekday(for: key)),
                completed: log?.isCompleted ?? false,
                ratio: log?.ratio ?? 0
            )
        }
    }
}
