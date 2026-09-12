import Foundation
import Testing
@testable import HabitCore

/// Pattern letters: C = completed, M = missed, S = unscheduled, P = partial (ratio 0.5, not completed).
/// The last letter is today.
func results(_ pattern: String) -> (results: [DayResult], today: DayKey) {
    let cal = DayCalendar(dayStartHour: 4, calendar: Fixed.calendar)
    var key = DayKey(raw: "2026-01-01")
    var out: [DayResult] = []
    for ch in pattern {
        switch ch {
        case "C": out.append(DayResult(dayKey: key, completed: true))
        case "M": out.append(DayResult(dayKey: key, completed: false))
        case "S": out.append(DayResult(dayKey: key, scheduled: false, completed: false))
        case "P": out.append(DayResult(dayKey: key, completed: false, ratio: 0.5))
        default: break
        }
        key = cal.key(byAdding: 1, to: key)
    }
    return (out, out.last!.dayKey)
}

@Suite("StreakCalculator")
struct StreakCalculatorTests {
    @Test func countsCompletedDays() {
        let (r, today) = results("CCCCC")
        #expect(StreakCalculator.currentStreak(r, today: today, graceMissesPerWeek: 1) == Streak(length: 5, gracesUsed: 0))
    }

    @Test func todayInProgressDoesNotBreak() {
        let (r, today) = results("CCCCM")
        #expect(StreakCalculator.currentStreak(r, today: today, graceMissesPerWeek: 1).length == 4)
    }

    @Test func oneMissPerWeekIsForgiven() {
        let (r, today) = results("CCMCC")
        #expect(StreakCalculator.currentStreak(r, today: today, graceMissesPerWeek: 1) == Streak(length: 4, gracesUsed: 1))
    }

    @Test func twoMissesInAWeekBreak() {
        let (r, today) = results("CCMCMC")
        let streak = StreakCalculator.currentStreak(r, today: today, graceMissesPerWeek: 1)
        #expect(streak.length == 2)
        #expect(streak.gracesUsed == 1)
    }

    @Test func missOlderThanAWeekDoesNotCount() {
        let (r, today) = results("CMCCCCCCCMC")
        #expect(StreakCalculator.currentStreak(r, today: today, graceMissesPerWeek: 1).length == 9, "9 completed days, the two misses are 8 days apart")
    }

    @Test func noGraceBreaksImmediately() {
        let (r, today) = results("CCMC")
        #expect(StreakCalculator.currentStreak(r, today: today, graceMissesPerWeek: 0).length == 1)
    }

    @Test func unscheduledDaysAreSkipped() {
        let (r, today) = results("CCSSCC")
        #expect(StreakCalculator.currentStreak(r, today: today, graceMissesPerWeek: 1).length == 4)
    }

    @Test func emptyHistory() {
        let (r, today) = results("M")
        #expect(StreakCalculator.currentStreak(r, today: today, graceMissesPerWeek: 1) == .zero)
        #expect(StreakCalculator.currentStreak([], today: today, graceMissesPerWeek: 1) == .zero)
    }

    @Test func bestStreak() {
        let (r, today) = results("CCCMMCC")
        #expect(StreakCalculator.bestStreak(r, today: today, graceMissesPerWeek: 1) == 3)
        let (r2, today2) = results("CMCCCMCC")
        #expect(StreakCalculator.bestStreak(r2, today: today2, graceMissesPerWeek: 1) == 4, "second miss within 7 days resets")
        let (r3, today3) = results("CMCCCCCCCMCC")
        #expect(StreakCalculator.bestStreak(r3, today: today3, graceMissesPerWeek: 1) == 10)
    }
}

@Suite("ConsistencyScore")
struct ConsistencyScoreTests {
    @Test func warmingUpUnderSevenDays() {
        let (r, today) = results("CCCM")
        let result = ConsistencyScore.compute(r, today: today)
        #expect(result.score == nil)
        #expect(result.isWarmingUp)
        #expect(result.historyDays == 3, "today-in-progress is excluded")
    }

    @Test func perfectMonthIsHundred() {
        let (r, today) = results(String(repeating: "C", count: 30))
        #expect(ConsistencyScore.compute(r, today: today).score == 100)
    }

    @Test func nothingDoneIsZero() {
        let (r, today) = results(String(repeating: "M", count: 30))
        #expect(ConsistencyScore.compute(r, today: today).score == 0)
    }

    @Test func partialProgressEarnsHalfCredit() {
        let (r, today) = results(String(repeating: "P", count: 30))
        #expect(ConsistencyScore.compute(r, today: today).score == 25)
    }

    @Test func recentMissesHurtMore() {
        let (old, t1) = results(String(repeating: "M", count: 10) + String(repeating: "C", count: 20))
        let (recent, t2) = results(String(repeating: "C", count: 20) + String(repeating: "M", count: 10))
        let oldScore = ConsistencyScore.compute(old, today: t1).score!
        let recentScore = ConsistencyScore.compute(recent, today: t2).score!
        #expect(oldScore > recentScore)
        #expect(oldScore >= 75)
        #expect(recentScore < 60)
    }

    @Test func windowLimitsHistory() {
        let (r, today) = results(String(repeating: "M", count: 60) + String(repeating: "C", count: 30))
        #expect(ConsistencyScore.compute(r, today: today, windowDays: 30).score == 100)
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
