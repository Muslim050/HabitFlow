import Foundation
import Testing
@testable import HabitCore

/// Pattern letters: C = completed, M = missed, S = unscheduled, P = partial (ratio 0.5, not completed).
/// The last letter is today. Each letter is one day-sized obligation; an unscheduled day creates
/// none at all, which is exactly what the schedule resolver does with a day it does not name.
func results(_ pattern: String) -> [ObligationResult] {
    let cal = DayCalendar(dayStartHour: 4, calendar: Fixed.calendar)
    var keys: [DayKey] = []
    var key = DayKey(raw: "2026-01-01")
    for _ in pattern {
        keys.append(key)
        key = cal.key(byAdding: 1, to: key)
    }
    guard let today = keys.last else { return [] }

    func day(_ key: DayKey, done: Int, partial: Double) -> ObligationResult {
        ObligationResult(start: key, end: key, period: .day, required: 1,
                         done: done, partial: partial, isOpen: key == today)
    }

    var out: [ObligationResult] = []
    for (character, key) in zip(pattern, keys) {
        switch character {
        case "C": out.append(day(key, done: 1, partial: 1))
        case "M": out.append(day(key, done: 0, partial: 0))
        case "P": out.append(day(key, done: 0, partial: 0.5))
        default: break   // "S": the schedule never named this day, so nothing is owed
        }
    }
    return out
}

@Suite("StreakCalculator")
struct StreakCalculatorTests {
    @Test func countsKeptObligations() {
        #expect(StreakCalculator.currentStreak(results("CCCCC"), freezesPerMonth: 1) == Streak(length: 5))
    }

    @Test func theRunningObligationNeverBreaksTheRun() {
        #expect(StreakCalculator.currentStreak(results("CCCCM"), freezesPerMonth: 1).length == 4)
    }

    @Test func aMissIsFrozenWhileTheMonthHasBudget() {
        let streak = StreakCalculator.currentStreak(results("CCMCC"), freezesPerMonth: 1)
        #expect(streak.length == 4, "a freeze keeps the run alive but is not itself a kept day")
        #expect(streak.gracesUsed == 1)
        #expect(streak.frozen == [DayKey(raw: "2026-01-03")])
    }

    @Test func aSecondMissInTheSameMonthBreaksTheRun() {
        let streak = StreakCalculator.currentStreak(results("CCMCMC"), freezesPerMonth: 1)
        #expect(streak.length == 2)
        #expect(streak.gracesUsed == 1)
    }

    @Test func distanceDoesNotMatterWithinAMonth() {
        // Under the old sliding-window rule these two misses were far enough apart to both be
        // forgiven. The budget is monthly now, so the second one ends the run.
        let streak = StreakCalculator.currentStreak(results("CMCCCCCCCMC"), freezesPerMonth: 1)
        #expect(streak.length == 8)
        #expect(streak.gracesUsed == 1)
    }

    @Test func eachMonthBringsItsOwnBudget() {
        // 2026-01-01 + 40 days runs into February: a miss in each month, one freeze each.
        let pattern = "M" + String(repeating: "C", count: 39) + "M" + String(repeating: "C", count: 5)
        let streak = StreakCalculator.currentStreak(pattern, freezes: 1)
        #expect(streak.gracesUsed == 2, "January and February are budgeted separately")
        #expect(streak.length == 44)
    }

    @Test func noBudgetBreaksImmediately() {
        #expect(StreakCalculator.currentStreak(results("CCMC"), freezesPerMonth: 0).length == 1)
    }

    @Test func unscheduledDaysAreSkipped() {
        #expect(StreakCalculator.currentStreak(results("CCSSCC"), freezesPerMonth: 1).length == 4)
    }

    @Test func emptyHistory() {
        #expect(StreakCalculator.currentStreak(results("M"), freezesPerMonth: 1) == .zero)
        #expect(StreakCalculator.currentStreak([], freezesPerMonth: 1) == .zero)
    }

    @Test func freezesLeftCountsWhatThisRunSpent() {
        let streak = StreakCalculator.currentStreak(results("CCMCC"), freezesPerMonth: 2)
        #expect(StreakCalculator.freezesLeft(in: DayKey(raw: "2026-01-05"), streak: streak, freezesPerMonth: 2) == 1)
        #expect(StreakCalculator.freezesLeft(in: DayKey(raw: "2026-02-05"), streak: streak, freezesPerMonth: 2) == 2)
    }

    @Test func bestStreak() {
        #expect(StreakCalculator.bestStreak(results("CCCMMCC"), freezesPerMonth: 1) == 3)
        #expect(StreakCalculator.bestStreak(results("CMCCCMCC"), freezesPerMonth: 1) == 4,
                "the month's one freeze went to the first miss, so the second resets")
        #expect(StreakCalculator.bestStreak(results("CMCCCCCCCMCC"), freezesPerMonth: 1) == 8)
    }
}

private extension StreakCalculator {
    /// Longer patterns read better without the `results(...)` wrapper in the middle of the call.
    static func currentStreak(_ pattern: String, freezes: Int) -> Streak {
        currentStreak(results(pattern), freezesPerMonth: freezes)
    }
}

@Suite("ConsistencyScore")
struct ConsistencyScoreTests {
    @Test func warmingUpUnderSevenDays() {
        let r = results("CCCM")
        let result = ConsistencyScore.compute(r)
        #expect(result.score == nil)
        #expect(result.isWarmingUp)
        #expect(result.history == 3, "today-in-progress is excluded")
    }

    @Test func perfectMonthIsHundred() {
        let r = results(String(repeating: "C", count: 30))
        #expect(ConsistencyScore.compute(r).score == 100)
    }

    @Test func nothingDoneIsZero() {
        let r = results(String(repeating: "M", count: 30))
        #expect(ConsistencyScore.compute(r).score == 0)
    }

    @Test func partialProgressEarnsHalfCredit() {
        let r = results(String(repeating: "P", count: 30))
        #expect(ConsistencyScore.compute(r).score == 25)
    }

    @Test func recentMissesHurtMore() {
        let old = results(String(repeating: "M", count: 10) + String(repeating: "C", count: 20))
        let recent = results(String(repeating: "C", count: 20) + String(repeating: "M", count: 10))
        let oldScore = ConsistencyScore.compute(old).score!
        let recentScore = ConsistencyScore.compute(recent).score!
        #expect(oldScore > recentScore)
        #expect(oldScore >= 75)
        #expect(recentScore < 60)
    }

    @Test func windowLimitsHistory() {
        let r = results(String(repeating: "M", count: 60) + String(repeating: "C", count: 30))
        #expect(ConsistencyScore.compute(r).score == 100)
    }
}

@Suite("DayResultBuilder")
@MainActor
struct DayResultBuilderTests {
    @Test func buildsFromCreationToToday() throws {
        let env = try TestEnv()
        let habit = try env.addHabit("Walk", rule: .healthQuantity(metric: .steps, target: 8000))
        habit.createdAt = env.clock.now.addingTimeInterval(-3 * 24 * 3600)
        let yesterday = env.engine.dayCalendar.key(byAdding: -1, to: env.today)
        let log = try env.repository.fetchOrCreateLog(habitID: habit.id, dayKey: yesterday, dayStart: env.clock.now, target: 8000)
        log.isCompleted = true
        log.progressValue = 8000
        try env.repository.save()

        let built = DayResultBuilder.build(habit: habit, logs: [log], calendar: env.engine.dayCalendar, today: env.today)
        #expect(built.count == 4)
        #expect(built[2].completed)
        #expect(built[3].completed == false)
        #expect(built.last?.dayKey == env.today)
    }
}

@Suite("HabitScore")
struct HabitScoreTests {
    @Test func startsAtZeroAndClimbsWithRepetition() {
        #expect(HabitScore.compute([]) == 0)
        let short = HabitScore.compute(results(String(repeating: "C", count: 5)))
        let long = HabitScore.compute(results(String(repeating: "C", count: 60)))
        #expect(short > 0)
        #expect(long > short, "strength is earned slowly; five days is not a habit")
        #expect(long > 90)
    }

    @Test func oneMissDipsTheScoreWithoutResettingIt() {
        // The miss sits second from the end: the last letter is today, and an unfinished today
        // is deliberately not counted at all.
        let clean = HabitScore.compute(results(String(repeating: "C", count: 41)))
        let oneMiss = HabitScore.compute(results(String(repeating: "C", count: 39) + "MC"))
        #expect(oneMiss < clean, "a miss has to cost something")
        #expect(oneMiss > clean - 15, "but nowhere near everything — this is the whole point")
        #expect(oneMiss > 50)
    }

    @Test func sustainedMissesDoBringItDown() {
        let score = HabitScore.compute(results(String(repeating: "C", count: 30) + String(repeating: "M", count: 30)))
        #expect(score < 25)
    }

    @Test func partialProgressEarnsPartialStrength() {
        let partial = HabitScore.compute(results(String(repeating: "P", count: 60)))
        let done = HabitScore.compute(results(String(repeating: "C", count: 60)))
        let nothing = HabitScore.compute(results(String(repeating: "M", count: 60)))
        #expect(nothing < partial && partial < done)
    }

    @Test func theRunningObligationOnlyCountsOnceKept() {
        // Last letter is today. An unfinished day must not pull the number down.
        let pending = HabitScore.compute(results(String(repeating: "C", count: 40) + "M"))
        let closed = HabitScore.compute(results(String(repeating: "C", count: 40)))
        #expect(pending == closed)
    }
}
