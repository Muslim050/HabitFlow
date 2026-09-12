import Foundation
import Testing
@testable import HabitCore

@Suite("InsightEngine")
struct InsightEngineTests {
    let calendar = DayCalendar(dayStartHour: 4, calendar: Fixed.calendar)
    var today: DayKey { DayKey(raw: "2026-03-02") }   // Monday

    /// Builds facts ending yesterday. `pattern`: C completed, M missed, S unscheduled.
    func facts(_ pattern: String, ratios: [Double]? = nil, hours: [Double]? = nil) -> [InsightEngine.DayFact] {
        let start = calendar.key(byAdding: -pattern.count, to: today)
        var key = start
        var result: [InsightEngine.DayFact] = []
        for (index, ch) in pattern.enumerated() {
            let completed = ch == "C"
            result.append(InsightEngine.DayFact(
                dayKey: key,
                scheduled: ch != "S",
                completed: completed,
                ratio: ratios?[index] ?? (completed ? 1 : 0),
                completedHour: completed ? hours?[index] : nil
            ))
            key = calendar.key(byAdding: 1, to: key)
        }
        return result
    }

    func history(_ pattern: String, automatic: Bool = false, ratios: [Double]? = nil, hours: [Double]? = nil, id: UUID = UUID()) -> InsightEngine.HabitHistory {
        InsightEngine.HabitHistory(habitID: id, isAutomatic: automatic, unitLabel: "steps",
                                   facts: facts(pattern, ratios: ratios, hours: hours))
    }

    // MARK: Weekly trend

    @Test func reportsImprovingWeek() throws {
        let insight = try #require(InsightEngine.weeklyTrend(history("MMMMMMMCCCCCCC"), calendar: calendar, today: today))
        #expect(insight.kind == .weeklyTrend)
        #expect(insight.primaryValue == 1)
        #expect(insight.secondaryValue == 0)
    }

    @Test func ignoresSmallWeeklyChange() {
        // 5/7 then 4/7 — a 14-point swing, below the 20-point floor.
        #expect(InsightEngine.weeklyTrend(history("CCCCCMMCCCCMMM"), calendar: calendar, today: today) == nil)
    }

    @Test func needsTwoFullWeeks() {
        #expect(InsightEngine.weeklyTrend(history("MMMCCC"), calendar: calendar, today: today) == nil)
    }

    // MARK: Weak weekday

    @Test func findsTheWeakWeekday() throws {
        // 8 weeks; every Saturday missed, everything else done.
        var pattern = ""
        for index in 0..<56 {
            let key = calendar.key(byAdding: -(56 - index), to: today)
            pattern += calendar.weekday(for: key) == 7 ? "M" : "C"
        }
        let insight = try #require(InsightEngine.weakWeekday(history(pattern), calendar: calendar, today: today))
        #expect(insight.primaryValue == 7, "Saturday")
        #expect(insight.secondaryValue == 0)
        #expect(insight.sampleDays >= InsightEngine.weekdayMinOccurrences)
    }

    @Test func noWeakWeekdayWhenEvenlySpread() {
        // Every third day missed: no weekday stands out enough.
        let pattern = (0..<56).map { $0 % 3 == 0 ? "M" : "C" }.joined()
        #expect(InsightEngine.weakWeekday(history(pattern), calendar: calendar, today: today) == nil)
    }

    @Test func noWeakWeekdayWithoutEnoughData() {
        #expect(InsightEngine.weakWeekday(history("CCMCCMC"), calendar: calendar, today: today) == nil)
    }

    // MARK: Pairing

    @Test func findsPairingBetweenHabits() throws {
        // Reading happens on the days sleep succeeded, not otherwise.
        let sleepPattern = String(repeating: "CM", count: 10)
        let readPattern = String(repeating: "CM", count: 10)
        let sleep = history(sleepPattern)
        let read = history(readPattern)
        let insight = try #require(InsightEngine.pairing(target: read, condition: sleep, today: today))
        #expect(insight.kind == .pairing)
        #expect(insight.primaryValue == 1)
        #expect(insight.secondaryValue == 0)
        #expect(insight.habitID == read.habitID)
        #expect(insight.relatedHabitID == sleep.habitID)
    }

    @Test func noPairingWhenIndependent() {
        let a = history(String(repeating: "CM", count: 10))
        let b = history(String(repeating: "CCMM", count: 5))
        #expect(InsightEngine.pairing(target: a, condition: b, today: today) == nil)
    }

    @Test func noPairingWithoutEnoughOverlap() {
        let a = history("CMCMCM")
        let b = history("CMCMCM")
        #expect(InsightEngine.pairing(target: a, condition: b, today: today) == nil)
    }

    // MARK: Near miss

    @Test func spotsNearMiss() throws {
        let ratios = Array(repeating: 0.92, count: 14)
        let insight = try #require(InsightEngine.nearMiss(history(String(repeating: "M", count: 14), automatic: true, ratios: ratios), today: today))
        #expect(insight.kind == .nearMiss)
        #expect(abs(insight.primaryValue - 0.92) < 0.0001)
        #expect(insight.unitLabel == "steps")
    }

    @Test func noNearMissWhenFarOff() {
        let ratios = Array(repeating: 0.4, count: 14)
        #expect(InsightEngine.nearMiss(history(String(repeating: "M", count: 14), automatic: true, ratios: ratios), today: today) == nil)
    }

    @Test func noNearMissForManualHabits() {
        let ratios = Array(repeating: 0.92, count: 14)
        #expect(InsightEngine.nearMiss(history(String(repeating: "M", count: 14), automatic: false, ratios: ratios), today: today) == nil)
    }

    @Test func noNearMissWhenAlreadySucceeding() {
        let ratios = Array(repeating: 0.95, count: 14)
        #expect(InsightEngine.nearMiss(history(String(repeating: "C", count: 14), automatic: true, ratios: ratios), today: today) == nil)
    }

    // MARK: Typical time

    @Test func findsTypicalTime() throws {
        let hours = [7.5, 8.0, 7.0, 8.5, 7.25, 8.25, 7.75, 8.1]
        let insight = try #require(InsightEngine.typicalTime(history(String(repeating: "C", count: 8), hours: hours), today: today))
        #expect(insight.kind == .typicalTime)
        #expect(insight.primaryValue > 7 && insight.primaryValue < 9)
    }

    @Test func noTypicalTimeWhenScattered() {
        let hours = [6.0, 12.0, 22.0, 9.0, 18.0, 7.0, 23.0, 14.0]
        #expect(InsightEngine.typicalTime(history(String(repeating: "C", count: 8), hours: hours), today: today) == nil)
    }

    // MARK: Aggregation

    @Test func sortsByPriorityAndLimits() {
        let ratios = Array(repeating: 0.9, count: 20)
        let nearMissHistory = history(String(repeating: "M", count: 20), automatic: true, ratios: ratios)
        let trendHistory = history("MMMMMMMCCCCCCC")
        let result = InsightEngine.insights(for: [nearMissHistory, trendHistory], calendar: calendar, today: today, limit: 3)
        #expect(result.count <= 3)
        #expect(result.first?.kind == .nearMiss, "near miss outranks a trend")
        #expect(result.map(\.priority) == result.map(\.priority).sorted(by: >))
    }

    @Test func emptyHistoryProducesNothing() {
        #expect(InsightEngine.insights(for: [], calendar: calendar, today: today).isEmpty)
        #expect(InsightEngine.insights(for: [history("CC")], calendar: calendar, today: today).isEmpty)
    }

    @Test func insightIDIsStable() {
        let habitID = UUID()
        let first = Insight(kind: .weeklyTrend, habitID: habitID, priority: 1)
        let second = Insight(kind: .weeklyTrend, habitID: habitID, priority: 99)
        #expect(first.id == second.id)
    }
}

@Suite("HistoryBuilder")
@MainActor
struct HistoryBuilderTests {
    @Test func buildsFactsAndSamplesFromLogs() throws {
        let env = try TestEnv()
        let habit = try env.addHabit("Walk", rule: .healthQuantity(metric: .steps, target: 8000))
        habit.createdAt = env.clock.now.addingTimeInterval(-5 * 24 * 3600)
        let calendar = env.engine.dayCalendar
        var logs: [DailyLog] = []
        for offset in 1...4 {
            let key = calendar.key(byAdding: -offset, to: env.today)
            let log = try env.repository.fetchOrCreateLog(habitID: habit.id, dayKey: key, dayStart: calendar.dayStart(for: key), target: 8000)
            log.progressValue = offset == 1 ? 12000 : 4000
            log.isCompleted = offset == 1
            log.completedAt = offset == 1 ? calendar.dayStart(for: key).addingTimeInterval(9 * 3600) : nil
            logs.append(log)
        }
        try env.repository.save()

        let history = HistoryBuilder.history(habit: habit, logs: logs, calendar: calendar, today: env.today)
        #expect(history.facts.count == 6)
        #expect(history.isAutomatic)
        let yesterday = try #require(history.facts.first { $0.dayKey == calendar.key(byAdding: -1, to: env.today) })
        #expect(yesterday.completed)
        #expect(yesterday.ratio == 1.5, "raw ratio is not clamped to 1")
        #expect(yesterday.completedHour == 13, "day starts at 04:00, so +9 h is 13:00")

        let samples = HistoryBuilder.adaptationSamples(habit: habit, logs: logs, calendar: calendar, today: env.today)
        #expect(samples.count == 4, "only days with a log, today excluded")
        #expect(samples.last?.value == 12000)
        #expect(samples.last?.completed == true)
    }
}
