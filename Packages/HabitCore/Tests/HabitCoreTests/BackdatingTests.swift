import Foundation
import Testing
@testable import HabitCore

/// Editing a day that has already passed: the single most requested thing missing from the app.
@Suite("Backdating")
@MainActor
struct BackdatingTests {
    let steps = HabitRule.healthQuantity(metric: .steps, target: 8000)

    // MARK: What may be edited

    @Test func editsADayInThePast() async throws {
        let env = try TestEnv()
        let habit = try env.addHabit("Walk", rule: steps, createdDaysAgo: 30)

        try env.engine.setManualCompletion(habitID: habit.id, completed: true, dayKey: env.day(-3))

        let log = try #require(try env.log(habit, -3))
        #expect(log.isCompleted)
        #expect(log.completionSource == .manualOverride)
        #expect(log.dayKey == env.day(-3).raw)
    }

    @Test func stampsCompletionInsideTheDayItBelongsTo() async throws {
        let env = try TestEnv()
        let habit = try env.addHabit("Walk", rule: steps, createdDaysAgo: 30)

        try env.engine.setManualCompletion(habitID: habit.id, completed: true, dayKey: env.day(-3))

        let log = try #require(try env.log(habit, -3))
        let completedAt = try #require(log.completedAt)
        let window = env.engine.dayCalendar.window(for: env.day(-3))
        #expect(window.contains(completedAt), "a day closed by hand must not be stamped with today's clock")
    }

    @Test func refusesADayOlderThanTheLimit() throws {
        let env = try TestEnv()
        env.settings.backdateLimitDays = 7
        let habit = try env.addHabit("Walk", rule: steps, createdDaysAgo: 60)

        #expect(throws: BackdateError.dayNotEditable(env.day(-8))) {
            try env.engine.setManualCompletion(habitID: habit.id, completed: true, dayKey: env.day(-8))
        }
        // The edge itself is still editable.
        try env.engine.setManualCompletion(habitID: habit.id, completed: true, dayKey: env.day(-7))
        #expect(try env.log(habit, -7)?.isCompleted == true)
    }

    @Test func refusesADayBeforeTheHabitExisted() throws {
        let env = try TestEnv()
        let habit = try env.addHabit("Walk", rule: steps, createdDaysAgo: 2)

        #expect(throws: BackdateError.dayNotEditable(env.day(-5))) {
            try env.engine.setManualCompletion(habitID: habit.id, completed: true, dayKey: env.day(-5))
        }
    }

    @Test func refusesTheFuture() throws {
        let env = try TestEnv()
        let habit = try env.addHabit("Walk", rule: steps, createdDaysAgo: 30)

        #expect(throws: BackdateError.dayNotEditable(env.day(1))) {
            try env.engine.setManualCompletion(habitID: habit.id, completed: true, dayKey: env.day(1))
        }
    }

    @Test func editableRangeFollowsTheSetting() throws {
        let env = try TestEnv()
        env.settings.backdateLimitDays = 14
        let range = env.engine.editableDayRange()
        #expect(range.upperBound == env.today)
        #expect(range.lowerBound == env.day(-14))
    }

    // MARK: The engine must not undo the edit

    @Test func evaluatingTodayLeavesAnEditedPastDayAlone() async throws {
        let env = try TestEnv()
        let habit = try env.addHabit("Walk", rule: steps, createdDaysAgo: 30)
        try env.engine.setManualCompletion(habitID: habit.id, completed: true, dayKey: env.day(-1))

        env.health.values[habit.id] = 0
        await env.engine.evaluateAll(reason: .foreground)

        let yesterday = try #require(try env.log(habit, -1))
        #expect(yesterday.isCompleted, "the engine only ever evaluates today")
        #expect(yesterday.completionSource == .manualOverride)
    }

    @Test func finalizingADayRespectsAnEditedPastDay() async throws {
        let env = try TestEnv()
        let habit = try env.addHabit("Walk", rule: steps, createdDaysAgo: 30)
        try env.engine.setManualCompletion(habitID: habit.id, completed: true, dayKey: env.day(-1))

        env.health.values[habit.id] = 0
        await env.engine.finalizeDay(env.day(-1))

        let yesterday = try #require(try env.log(habit, -1))
        #expect(yesterday.isCompleted, "a manual override outranks an empty Health day")
        #expect(yesterday.completionSource == .manualOverride)
    }

    @Test func clearingAnOverrideOnAPastDayHandsItBackToTheEngine() async throws {
        let env = try TestEnv()
        let habit = try env.addHabit("Walk", rule: steps, createdDaysAgo: 30)
        try env.engine.setManualCompletion(habitID: habit.id, completed: true, dayKey: env.day(-1))
        env.health.values[habit.id] = 9000

        try await env.engine.clearOverride(habitID: habit.id, dayKey: env.day(-1))

        let yesterday = try #require(try env.log(habit, -1))
        #expect(yesterday.completionSource == .auto, "Health owns the day again")
        #expect(yesterday.progressValue == 9000)
    }

    // MARK: Correcting a measured value

    @Test func writesAMeasuredValueByHand() throws {
        let env = try TestEnv()
        let habit = try env.addHabit("Walk", rule: steps, createdDaysAgo: 30)

        try env.engine.setManualValue(habitID: habit.id, value: 9500, dayKey: env.day(-2))

        let log = try #require(try env.log(habit, -2))
        #expect(log.progressValue == 9500)
        #expect(log.isCompleted, "9 500 clears the 8 000 target")
        #expect(log.completionSource == .manualOverride)
    }

    @Test func aValueBelowTargetDoesNotCloseTheDay() throws {
        let env = try TestEnv()
        let habit = try env.addHabit("Walk", rule: steps, createdDaysAgo: 30)

        try env.engine.setManualValue(habitID: habit.id, value: 5000, dayKey: env.day(-2))

        let log = try #require(try env.log(habit, -2))
        #expect(!log.isCompleted)
        #expect(log.completedAt == nil)
    }

    @Test func comparesAgainstTheTargetThatDayWasMeasuredAgainst() throws {
        let env = try TestEnv()
        let habit = try env.addHabit("Walk", rule: steps, createdDaysAgo: 30)
        // That day was judged against 5 000; adaptive goals have since raised the habit to 10 000.
        let key = env.day(-4)
        _ = try env.repository.fetchOrCreateLog(
            habitID: habit.id, dayKey: key,
            dayStart: env.engine.dayCalendar.dayStart(for: key), target: 5000
        )
        habit.rule = .healthQuantity(metric: .steps, target: 10000)
        try env.repository.save()

        try env.engine.setManualValue(habitID: habit.id, value: 6000, dayKey: key)

        let log = try #require(try env.log(habit, -4))
        #expect(log.targetValue == 5000)
        #expect(log.isCompleted, "history is judged by the goal that was in force, not today's")
    }

    @Test func refusesAMeasuredValueOnAManualHabit() throws {
        let env = try TestEnv()
        let habit = try env.addHabit("Read", rule: .manual, createdDaysAgo: 30)

        #expect(throws: BackdateError.habitIsNotMeasured(habit.id)) {
            try env.engine.setManualValue(habitID: habit.id, value: 3, dayKey: env.day(-1))
        }
    }

    // MARK: Derived metrics follow

    @Test func editingAPastDayChangesTheStreak() throws {
        let env = try TestEnv()
        env.settings.graceMissesPerWeek = 0
        let habit = try env.addHabit("Walk", rule: .manual, createdDaysAgo: 30)
        // Yesterday and the day before are closed; the gap three days back breaks the chain.
        for offset in [-1, -2, -4, -5] {
            try env.engine.setManualCompletion(habitID: habit.id, completed: true, dayKey: env.day(offset))
        }
        let before = try stats(env, habit)
        #expect(before.currentStreak.length == 2)

        try env.engine.setManualCompletion(habitID: habit.id, completed: true, dayKey: env.day(-3))

        let after = try stats(env, habit)
        #expect(after.currentStreak.length == 5, "filling the gap joins both runs")
    }

    private func stats(_ env: TestEnv, _ habit: Habit) throws -> HabitStats {
        let logs = try env.repository.logs(habitID: habit.id, from: env.day(-30), to: env.today)
        return HabitStats.compute(
            habit: habit, logs: logs, calendar: env.engine.dayCalendar,
            today: env.today, graceMissesPerWeek: env.settings.graceMissesPerWeek
        )
    }
}
