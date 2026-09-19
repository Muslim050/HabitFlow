import Foundation

/// One day in a habit's history, as the grids and heat maps see it.
public struct DayResult: Sendable, Equatable {
    public var dayKey: DayKey
    /// What the schedule asked of this day. `.flexible` days belong to a period with a quota and
    /// can never be a miss on their own.
    public var obligation: DayObligation
    public var completed: Bool
    /// Partial progress 0…1 (automatic habits only; manual habits are 0 or 1).
    public var ratio: Double

    public init(dayKey: DayKey, obligation: DayObligation = .required, completed: Bool, ratio: Double? = nil) {
        self.dayKey = dayKey
        self.obligation = obligation
        self.completed = completed
        self.ratio = ratio ?? (completed ? 1 : 0)
    }

    /// The habit was live that day — named by the schedule, or inside an open quota period.
    public var isDue: Bool { obligation.isDue }
}

public enum DayResultBuilder {
    /// Builds ascending results from the habit's creation day (or `from`) through `today`.
    /// Days without a log count as not completed.
    public static func build(habit: Habit, logs: [DailyLog], calendar: DayCalendar, today: DayKey, from: DayKey? = nil) -> [DayResult] {
        let resolver = ScheduleResolver(habit: habit, calendar: calendar)
        let firstKey = from ?? calendar.dayKey(for: habit.createdAt)
        let byKey = Dictionary(logs.map { ($0.dayKey, $0) }, uniquingKeysWith: { a, b in a.updatedAt >= b.updatedAt ? a : b })
        return calendar.keys(from: firstKey, to: today).map { key in
            let log = byKey[key.raw]
            return DayResult(
                dayKey: key,
                obligation: resolver.obligation(on: key),
                completed: log?.isCompleted ?? false,
                ratio: log?.ratio ?? 0
            )
        }
    }
}
