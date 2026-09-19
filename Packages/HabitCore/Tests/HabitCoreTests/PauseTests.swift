import Foundation
import Testing
@testable import HabitCore

/// A holiday is not a slump. Paused days create no obligation, so there is nothing to keep and
/// nothing to lose — every number simply stands still across the gap.
@Suite("Pauses")
@MainActor
struct PauseTests {
    private var week: DayCalendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = Fixed.timeZone
        c.locale = Locale(identifier: "en_US_POSIX")
        c.firstWeekday = 2
        return DayCalendar(dayStartHour: 4, calendar: c)
    }

    /// Saturday 2026-09-19.
    private func environment() throws -> TestEnv { try TestEnv(now: Fixed.date(2026, 9, 19, 10, 0)) }

    private func pause(_ env: TestEnv, habit: Habit?, from: String, to: String?,
                       reason: PauseReason = .vacation) throws -> HabitPause {
        let row = HabitPause(habitID: habit?.id, start: DayKey(raw: from),
                             end: to.map { DayKey(raw: $0) }, reason: reason)
        env.repository.insert(row)
        try env.repository.save()
        return row
    }

    private func complete(_ env: TestEnv, _ habit: Habit, _ days: [String]) throws {
        for day in days {
            try env.engine.setManualCompletion(habitID: habit.id, completed: true, dayKey: DayKey(raw: day))
        }
    }

    private func stats(_ env: TestEnv, _ habit: Habit) throws -> HabitStats {
        let logs = try env.repository.logs(habitID: habit.id, from: DayKey(raw: "2026-08-01"), to: env.today)
        return HabitStats.compute(habit: habit, logs: logs, calendar: week, today: env.today,
                                  freezesPerMonth: 0, pauses: try env.repository.pauses())
    }

    // MARK: Days inside a pause owe nothing

    @Test func aPausedDayIsNeitherDueNorMissed() throws {
        let env = try environment()
        let habit = try env.addHabit("Walk", rule: .manual, createdDaysAgo: 30)
        _ = try pause(env, habit: habit, from: "2026-09-10", to: "2026-09-16")
        let spans = try env.repository.pauses().spans(for: habit.id)

        #expect(habit.obligation(on: DayKey(raw: "2026-09-12"), calendar: week, pauses: spans) == .paused)
        #expect(!habit.isDue(on: DayKey(raw: "2026-09-12"), calendar: week, pauses: spans))
        #expect(habit.obligation(on: DayKey(raw: "2026-09-17"), calendar: week, pauses: spans) == .required,
                "the day after the pause is asked for again")
    }

    @Test func aGlobalPauseCoversEveryHabit() throws {
        let env = try environment()
        let walk = try env.addHabit("Walk", rule: .manual, createdDaysAgo: 30)
        let read = try env.addHabit("Read", rule: .manual, createdDaysAgo: 30)
        _ = try pause(env, habit: nil, from: "2026-09-10", to: "2026-09-16")
        let all = try env.repository.pauses()

        for habit in [walk, read] {
            #expect(habit.obligation(on: DayKey(raw: "2026-09-12"), calendar: week,
                                     pauses: all.spans(for: habit.id)) == .paused)
        }
    }

    @Test func aRunningPauseHasNoEnd() throws {
        let env = try environment()
        let habit = try env.addHabit("Walk", rule: .manual, createdDaysAgo: 30)
        let row = try pause(env, habit: habit, from: "2026-09-10", to: nil)
        #expect(row.isRunning)
        #expect(row.span.contains(DayKey(raw: "2027-01-01")), "with no end it keeps covering days")

        row.end(on: DayKey(raw: "2026-09-16"))
        #expect(!row.isRunning)
        #expect(!row.span.contains(DayKey(raw: "2026-09-17")))
    }

    // MARK: Nothing moves across the gap

    @Test func aWeekOffLeavesTheStreakExactlyWhereItWas() throws {
        let env = try environment()
        let habit = try env.addHabit("Walk", rule: .manual, createdDaysAgo: 30)
        // Four kept days, then a week away, then two kept days. No freezes, so any miss would show.
        try complete(env, habit, ["2026-09-06", "2026-09-07", "2026-09-08", "2026-09-09",
                                  "2026-09-17", "2026-09-18"])
        let withoutPause = try stats(env, habit).currentStreak.length
        #expect(withoutPause == 2, "without a pause the gap breaks the run")

        _ = try pause(env, habit: habit, from: "2026-09-10", to: "2026-09-16")

        let withPause = try stats(env, habit)
        #expect(withPause.currentStreak.length == 6, "the run reaches across the holiday untouched")
        #expect(withPause.currentStreak.gracesUsed == 0, "and it cost no freezes to do it")
    }

    @Test func pausedDaysDoNotEnterTheRateOrTheScore() throws {
        let env = try environment()
        let habit = try env.addHabit("Walk", rule: .manual, createdDaysAgo: 30)
        try complete(env, habit, ["2026-09-06", "2026-09-07", "2026-09-08", "2026-09-09",
                                  "2026-09-17", "2026-09-18"])
        let before = try stats(env, habit)

        _ = try pause(env, habit: habit, from: "2026-09-10", to: "2026-09-16")
        let after = try stats(env, habit)

        #expect(after.requiredCount == before.requiredCount - 7, "seven days stop being asked for")
        #expect(after.completedCount == before.completedCount, "and none of them was a completion")
        #expect(after.completionRate > before.completionRate, "the denominator shrank, the numerator did not")
        #expect(after.habitScore > before.habitScore)
    }

    @Test func aPausedWeekAsksForNothingAtAll() throws {
        let env = try environment()
        let habit = try env.addHabit("Gym", rule: .manual, schedule: .timesPerWeek(count: 3), createdDaysAgo: 60)
        _ = try pause(env, habit: habit, from: "2026-09-07", to: "2026-09-13")

        let logs = try env.repository.logs(habitID: habit.id, from: DayKey(raw: "2026-08-01"), to: env.today)
        let built = ObligationResultBuilder.build(habit: habit, logs: logs, calendar: week, today: env.today,
                                                  pauses: try env.repository.pauses(),
                                                  from: DayKey(raw: "2026-08-31"))
        #expect(!built.contains { $0.start == DayKey(raw: "2026-09-07") },
                "a week swallowed whole by a pause is not an obligation")
        #expect(built.contains { $0.start == DayKey(raw: "2026-08-31") },
                "and the walk carries on past it rather than stopping")
        #expect(built.contains { $0.start == DayKey(raw: "2026-09-14") })
    }

    @Test func aPartlyPausedWeekAsksForLess() throws {
        let env = try environment()
        let habit = try env.addHabit("Gym", rule: .manual, schedule: .timesPerWeek(count: 3), createdDaysAgo: 60)
        // Monday to Thursday off: three of the week's seven days remain.
        _ = try pause(env, habit: habit, from: "2026-09-07", to: "2026-09-10")

        let resolver = ScheduleResolver(habit: habit, calendar: week,
                                        pauses: try env.repository.pauses().spans(for: habit.id))
        let week1 = try #require(resolver.obligation(containing: DayKey(raw: "2026-09-11")))
        #expect(week1.quota == 1, "three days left out of seven, so about one of the three")
        #expect(week1.start == DayKey(raw: "2026-09-11"), "clipped to the first day back")
    }

    // MARK: The engine and the adaptive goal

    @Test func theEngineLeavesNoLogsBehindOnAPausedDay() async throws {
        let env = try TestEnv()
        let habit = try env.addHabit("Walk", rule: .healthQuantity(metric: .steps, target: 8000))
        _ = try pause(env, habit: habit, from: env.today.raw, to: nil)
        env.health.values[habit.id] = 12000

        await env.engine.evaluateAll(reason: .foreground)

        #expect(try env.log(habit) == nil, "a paused day is not evaluated, so no empty log is written")
        #expect(env.health.snapshotCalls == 0)
    }

    @Test func daysInsideAPauseNeverReachTheAdaptiveGoal() throws {
        let env = try environment()
        let habit = try env.addHabit("Walk", rule: .healthQuantity(metric: .steps, target: 8000),
                                     createdDaysAgo: 60)
        // A stretch of empty days that would read as failure, all of them inside a holiday.
        for day in 10...16 {
            let key = DayKey(raw: "2026-09-\(day)")
            _ = try env.repository.fetchOrCreateLog(habitID: habit.id, dayKey: key,
                                                    dayStart: week.dayStart(for: key), target: 8000)
        }
        try env.repository.save()
        _ = try pause(env, habit: habit, from: "2026-09-10", to: "2026-09-16", reason: .sick)

        let logs = try env.repository.logs(habitID: habit.id, from: DayKey(raw: "2026-08-01"), to: env.today)
        let samples = HistoryBuilder.adaptationSamples(habit: habit, logs: logs, calendar: week,
                                                       today: env.today, pauses: try env.repository.pauses())
        #expect(samples.isEmpty, "a week of illness must not talk the goal down")
    }
}
