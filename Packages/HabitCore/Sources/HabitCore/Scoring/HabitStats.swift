import Foundation

/// Everything the detail screen and widgets show about one habit's history.
///
/// `currentStreak` and `bestStreak` are counted in `period` units, not always in days: a
/// "three times a week" habit has a streak of weeks. Anything displaying them must say which.
public struct HabitStats: Sendable, Equatable {
    public var results: [DayResult]
    public var obligations: [ObligationResult]
    public var period: SchedulePeriod
    public var currentStreak: Streak
    public var bestStreak: Int
    public var consistency: ConsistencyScore.Result
    /// Completions that counted, never more than the obligation asked for.
    public var completedCount: Int
    /// What the obligations in range asked for in total.
    public var requiredCount: Int

    public static func compute(habit: Habit, logs: [DailyLog], calendar: DayCalendar, today: DayKey, graceMissesPerWeek: Int) -> HabitStats {
        let results = DayResultBuilder.build(habit: habit, logs: logs, calendar: calendar, today: today)
        let obligations = ObligationResultBuilder.build(habit: habit, logs: logs, calendar: calendar, today: today)
        return HabitStats(
            results: results,
            obligations: obligations,
            period: habit.schedule.period,
            currentStreak: StreakCalculator.currentStreak(obligations, graceMissesPerWeek: graceMissesPerWeek),
            bestStreak: StreakCalculator.bestStreak(obligations, graceMissesPerWeek: graceMissesPerWeek),
            consistency: ConsistencyScore.compute(obligations),
            completedCount: obligations.reduce(0) { $0 + min($1.done, $1.required) },
            requiredCount: obligations.reduce(0) { $0 + $1.required }
        )
    }
}
