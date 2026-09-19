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
    @Test func countsCompletedDays() {
        let r = results("CCCCC")
        #expect(StreakCalculator.currentStreak(r, graceMissesPerWeek: 1) == Streak(length: 5, gracesUsed: 0))
    }

    @Test func todayInProgressDoesNotBreak() {
        let r = results("CCCCM")
        #expect(StreakCalculator.currentStreak(r, graceMissesPerWeek: 1).length == 4)
    }

    @Test func oneMissPerWeekIsForgiven() {
        let r = results("CCMCC")
        #expect(StreakCalculator.currentStreak(r, graceMissesPerWeek: 1) == Streak(length: 4, gracesUsed: 1))
    }

    @Test func twoMissesInAWeekBreak() {
        let r = results("CCMCMC")
        let streak = StreakCalculator.currentStreak(r, graceMissesPerWeek: 1)
        #expect(streak.length == 2)
        #expect(streak.gracesUsed == 1)
    }

    @Test func missOlderThanAWeekDoesNotCount() {
        let r = results("CMCCCCCCCMC")
        #expect(StreakCalculator.currentStreak(r, graceMissesPerWeek: 1).length == 9, "9 completed days, the two misses are 8 days apart")
    }

    @Test func noGraceBreaksImmediately() {
        let r = results("CCMC")
        #expect(StreakCalculator.currentStreak(r, graceMissesPerWeek: 0).length == 1)
    }

    @Test func unscheduledDaysAreSkipped() {
        let r = results("CCSSCC")
        #expect(StreakCalculator.currentStreak(r, graceMissesPerWeek: 1).length == 4)
    }

    @Test func emptyHistory() {
        let r = results("M")
        #expect(StreakCalculator.currentStreak(r, graceMissesPerWeek: 1) == .zero)
        #expect(StreakCalculator.currentStreak([], graceMissesPerWeek: 1) == .zero)
    }

    @Test func bestStreak() {
        let r = results("CCCMMCC")
        #expect(StreakCalculator.bestStreak(r, graceMissesPerWeek: 1) == 3)
        let r2 = results("CMCCCMCC")
        #expect(StreakCalculator.bestStreak(r2, graceMissesPerWeek: 1) == 4, "second miss within 7 days resets")
        let r3 = results("CMCCCCCCCMCC")
        #expect(StreakCalculator.bestStreak(r3, graceMissesPerWeek: 1) == 10)
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
