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
    /// Which headline number this habit reports.
    public var progressModel: ProgressModel
    /// Loop-style strength, 0…100. Always computed: the models are cheap and the detail screen
    /// shows the others as secondary rows whichever one is the headline.
    public var habitScore: Int
    /// Share of obligations kept over the recent window, 0…1.
    public var completionRate: Double
    public var totalCompletions: Int
    /// Days covered by an obligation the freeze budget saved, so the heat map can mark them
    /// as frozen rather than leave them looking like plain misses.
    public var frozenDays: Set<DayKey>

    public static func compute(habit: Habit, logs: [DailyLog], calendar: DayCalendar, today: DayKey,
                               freezesPerMonth: Int, pauses: [HabitPause] = []) -> HabitStats {
        let results = DayResultBuilder.build(habit: habit, logs: logs, calendar: calendar, today: today, pauses: pauses)
        let obligations = ObligationResultBuilder.build(habit: habit, logs: logs, calendar: calendar, today: today, pauses: pauses)
        let streak = StreakCalculator.currentStreak(obligations, freezesPerMonth: freezesPerMonth)
        return HabitStats(
            results: results,
            obligations: obligations,
            period: habit.schedule.period,
            currentStreak: streak,
            bestStreak: StreakCalculator.bestStreak(obligations, freezesPerMonth: freezesPerMonth),
            consistency: ConsistencyScore.compute(obligations),
            completedCount: obligations.reduce(0) { $0 + min($1.done, $1.required) },
            requiredCount: obligations.reduce(0) { $0 + $1.required },
            progressModel: habit.progressModel,
            habitScore: HabitScore.compute(obligations),
            completionRate: Self.rate(obligations),
            totalCompletions: obligations.count { $0.fulfilled },
            frozenDays: Self.days(of: streak.frozen, in: obligations, calendar: calendar)
        )
    }

    /// Plain share of kept obligations over the same window the consistency index uses, so the
    /// two numbers describe the same stretch of history and only differ in the weighting.
    private static func rate(_ obligations: [ObligationResult]) -> Double {
        let period = obligations.last?.period ?? .day
        let judged = obligations.filter { !$0.isOpen || $0.fulfilled }
            .suffix(ConsistencyScore.window(for: period).span)
        guard !judged.isEmpty else { return 0 }
        return Double(judged.count { $0.fulfilled }) / Double(judged.count)
    }

    private static func days(of frozen: [DayKey], in obligations: [ObligationResult], calendar: DayCalendar) -> Set<DayKey> {
        let byStart = Dictionary(obligations.map { ($0.start, $0) }, uniquingKeysWith: { a, _ in a })
        return frozen.reduce(into: Set<DayKey>()) { days, start in
            guard let obligation = byStart[start] else { return }
            days.formUnion(calendar.keys(from: obligation.start, to: obligation.end))
        }
    }
}
