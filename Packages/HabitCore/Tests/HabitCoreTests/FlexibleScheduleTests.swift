import Foundation
import Testing
@testable import HabitCore

/// "Three times a week" end to end: the request sheet-workers make, and the one that breaks
/// every assumption that a habit is owed on a particular day.
@Suite("Flexible schedules")
@MainActor
struct FlexibleScheduleTests {
    /// Monday-first, so the weeks below are 08-31…09-06, 09-07…09-13 and 09-14…09-20.
    private var week: DayCalendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = Fixed.timeZone
        c.locale = Locale(identifier: "en_US_POSIX")
        c.firstWeekday = 2
        return DayCalendar(dayStartHour: 4, calendar: c)
    }

    /// Saturday 2026-09-19: two whole weeks behind it, and its own week still running.
    private func environment() throws -> TestEnv { try TestEnv(now: Fixed.date(2026, 9, 19, 10, 0)) }

    private func threeTimesAWeek(_ env: TestEnv) throws -> Habit {
        try env.addHabit("Gym", rule: .manual, schedule: .timesPerWeek(count: 3), createdDaysAgo: 60)
    }

    private func complete(_ env: TestEnv, _ habit: Habit, _ days: [String]) throws {
        for day in days {
            try env.engine.setManualCompletion(habitID: habit.id, completed: true, dayKey: DayKey(raw: day))
        }
    }

    private func obligations(_ env: TestEnv, _ habit: Habit) throws -> [ObligationResult] {
        let logs = try env.repository.logs(habitID: habit.id, from: DayKey(raw: "2026-08-01"), to: env.today)
        return ObligationResultBuilder.build(habit: habit, logs: logs, calendar: week,
                                             today: env.today, from: DayKey(raw: "2026-08-31"))
    }

    // MARK: The quota, not the day

    @Test func anyThreeDaysFulfilTheWeek() throws {
        let env = try environment()
        let habit = try threeTimesAWeek(env)
        // Tuesday, Thursday, Sunday — no two the same weekday, none of them "the" day.
        try complete(env, habit, ["2026-09-08", "2026-09-10", "2026-09-13"])

        let built = try obligations(env, habit)
        let lastWeek = try #require(built.first { $0.start == DayKey(raw: "2026-09-07") })
        #expect(lastWeek.required == 3)
        #expect(lastWeek.done == 3)
        #expect(lastWeek.fulfilled)
        #expect(!lastWeek.isOpen)
    }

    @Test func twoOfThreeMissesTheWeek() throws {
        let env = try environment()
        let habit = try threeTimesAWeek(env)
        try complete(env, habit, ["2026-09-08", "2026-09-10"])

        let built = try obligations(env, habit)
        let lastWeek = try #require(built.first { $0.start == DayKey(raw: "2026-09-07") })
        #expect(!lastWeek.fulfilled)
        #expect(abs(lastWeek.credit - 2.0 / 3.0) < 0.001, "two thirds of the quota earns two thirds of the credit")
    }

    // MARK: Streaks count weeks

    @Test func theStreakCountsWeeksAndSurvivesAnEmptyRunningWeek() throws {
        let env = try environment()
        let habit = try threeTimesAWeek(env)
        try complete(env, habit, ["2026-08-31", "2026-09-02", "2026-09-04",
                                  "2026-09-08", "2026-09-10", "2026-09-13"])
        // Nothing yet this week, and the week is not over.

        let streak = try StreakCalculator.currentStreak(obligations(env, habit), freezesPerMonth: 1)
        #expect(streak.length == 2, "two whole weeks kept; the running one is not judged yet")
        #expect(streak.gracesUsed == 0)
    }

    @Test func aMissedWeekIsForgivenOnce() throws {
        let env = try environment()
        let habit = try threeTimesAWeek(env)
        try complete(env, habit, ["2026-08-31", "2026-09-02", "2026-09-04"])
        // Last week only got two of three.
        try complete(env, habit, ["2026-09-08", "2026-09-10"])

        let streak = try StreakCalculator.currentStreak(obligations(env, habit), freezesPerMonth: 1)
        #expect(streak.length == 1)
        #expect(streak.gracesUsed == 1)
    }

    @Test func statsReportTheWeekAsTheUnit() throws {
        let env = try environment()
        let habit = try threeTimesAWeek(env)
        try complete(env, habit, ["2026-09-08", "2026-09-10", "2026-09-13"])

        let logs = try env.repository.logs(habitID: habit.id, from: DayKey(raw: "2026-08-01"), to: env.today)
        let stats = HabitStats.compute(habit: habit, logs: logs, calendar: week,
                                       today: env.today, freezesPerMonth: 1)
        #expect(stats.period == .week)
        #expect(stats.consistency.period == .week)
        #expect(stats.consistency.minimum == 3, "three weeks of history, not seven days")
    }

    // MARK: Nothing treats a spare day as a failure

    @Test func theMatrixNeverPaintsASpareDayAsMissed() throws {
        let env = try environment()
        let habit = try threeTimesAWeek(env)
        try complete(env, habit, ["2026-09-14", "2026-09-16", "2026-09-18"])

        let logs = try env.repository.logs(from: DayKey(raw: "2026-08-01"), to: env.today)
        let matrix = HabitMatrix.build(habits: [habit], logs: logs, calendar: week,
                                       today: env.today, days: 7)
        let row = try #require(matrix.rows.first)
        #expect(!row.states.contains(MatrixState.missed), "a quota habit owes the week, never a given day")
        #expect(row.doneCount == 3)
        #expect(row.scheduledCount == 3, "the week's quota, not seven days")
    }

    @Test func theActivityGridOwesAFlexibleHabitOnNoParticularDay() throws {
        let env = try environment()
        let habit = try threeTimesAWeek(env)
        try complete(env, habit, ["2026-09-16"])

        let logs = try env.repository.logs(from: DayKey(raw: "2026-08-01"), to: env.today)
        let grid = ActivityGrid.build(habits: [habit], logs: logs, calendar: week, today: env.today, weeks: 2)
        let days = grid.days.compactMap { $0 }
        #expect(days.allSatisfy { $0.scheduled == 0 }, "no date is owed")
        let worked = try #require(days.first { $0.dayKey == DayKey(raw: "2026-09-16") })
        #expect(worked.level == 4, "a day that was used still counts as a full day")
        let spare = try #require(days.first { $0.dayKey == DayKey(raw: "2026-09-17") })
        #expect(spare.isOffDay, "a day that was not used is simply empty")
    }

    @Test func untouchedSpareDaysDoNotDragTheGoalDown() throws {
        let env = try environment()
        let habit = try env.addHabit("Walk", rule: .healthQuantity(metric: .steps, target: 8000),
                                     schedule: .timesPerWeek(count: 3), createdDaysAgo: 60)
        // Three good days, and a stack of days with an empty log because the engine ran anyway.
        for day in ["2026-09-08", "2026-09-10", "2026-09-13"] {
            let key = DayKey(raw: day)
            let log = try env.repository.fetchOrCreateLog(habitID: habit.id, dayKey: key,
                                                          dayStart: week.dayStart(for: key), target: 8000)
            log.progressValue = 9000
            log.isCompleted = true
        }
        for day in ["2026-09-09", "2026-09-11", "2026-09-12"] {
            let key = DayKey(raw: day)
            _ = try env.repository.fetchOrCreateLog(habitID: habit.id, dayKey: key,
                                                    dayStart: week.dayStart(for: key), target: 8000)
        }
        try env.repository.save()

        let logs = try env.repository.logs(habitID: habit.id, from: DayKey(raw: "2026-08-01"), to: env.today)
        let samples = HistoryBuilder.adaptationSamples(habit: habit, logs: logs, calendar: week, today: env.today)
        #expect(samples.count == 3, "a day the user did not pick is not evidence the goal is too hard")
        #expect(samples.filter(\.completed).count == samples.count)
    }
}
