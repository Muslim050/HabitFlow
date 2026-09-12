import Foundation

/// Everything the detail screen and widgets show about one habit's history.
public struct HabitStats: Sendable, Equatable {
    public var results: [DayResult]
    public var currentStreak: Streak
    public var bestStreak: Int
    public var consistency: ConsistencyScore.Result
    public var completedDays: Int
    public var scheduledDays: Int

    public static func compute(habit: Habit, logs: [DailyLog], calendar: DayCalendar, today: DayKey, graceMissesPerWeek: Int) -> HabitStats {
        let results = DayResultBuilder.build(habit: habit, logs: logs, calendar: calendar, today: today)
        let scheduled = results.filter { $0.scheduled && $0.dayKey <= today }
        return HabitStats(
            results: results,
            currentStreak: StreakCalculator.currentStreak(results, today: today, graceMissesPerWeek: graceMissesPerWeek),
            bestStreak: StreakCalculator.bestStreak(results, today: today, graceMissesPerWeek: graceMissesPerWeek),
            consistency: ConsistencyScore.compute(results, today: today),
            completedDays: scheduled.filter(\.completed).count,
            scheduledDays: scheduled.count
        )
    }
}
