import Foundation
import SwiftData
import Testing
@testable import HabitCore

@Suite("AnalysisEngine")
@MainActor
struct AnalysisEngineTests {
    /// In-memory store plus a fixed clock, so nothing depends on the machine's data or time.
    @MainActor
    struct Fixture {
        /// Held so the store outlives the test body.
        let container: ModelContainer
        let repository: SwiftDataHabitRepository
        let settings: AppSettings
        let engine: AnalysisEngine
        let now: Date

        init(now: Date = Date()) throws {
            container = try ModelContainerFactory.inMemory()
            repository = SwiftDataHabitRepository(container: container)
            settings = AppSettings(defaults: UserDefaults(suiteName: "AnalysisEngineTests-\(UUID().uuidString)")!)
            self.now = now
            engine = AnalysisEngine(repository: repository, settings: settings, clock: { now })
        }

        var calendar: DayCalendar { settings.dayCalendar }
        var today: DayKey { calendar.dayKey(for: now) }

        @discardableResult
        func habit(_ name: String, rule: HabitRule, mode: GoalAdaptationMode = .suggest) throws -> Habit {
            let habit = Habit(name: name, rule: rule, createdAt: now.addingTimeInterval(-40 * 24 * 3600))
            habit.adaptationMode = mode
            repository.insert(habit)
            try repository.save()
            return habit
        }

        /// Writes one log per day for the last `values.count` days, ending yesterday.
        func seed(_ habit: Habit, values: [Double], target: Double) throws {
            for (offset, value) in values.reversed().enumerated() {
                let key = calendar.key(byAdding: -(offset + 1), to: today)
                let log = try repository.fetchOrCreateLog(habitID: habit.id, dayKey: key,
                                                          dayStart: calendar.dayStart(for: key), target: target)
                log.progressValue = value
                log.targetValue = target
                log.isCompleted = value >= target
                log.completedAt = log.isCompleted ? calendar.dayStart(for: key).addingTimeInterval(5 * 3600) : nil
            }
            try repository.save()
        }
    }

    @Test func proposesRaisingAGoalThatIsAlwaysExceeded() throws {
        let fixture = try Fixture()
        let habit = try fixture.habit("Walk", rule: .healthQuantity(metric: .steps, target: 8000))
        try fixture.seed(habit, values: Array(repeating: 11000, count: 16), target: 8000)

        let result = fixture.engine.refresh()

        let proposal = try #require(result.proposals.first)
        #expect(proposal.habitID == habit.id)
        #expect(proposal.direction == .increase)
        #expect(proposal.proposedTarget > 8000)
        #expect(habit.rule.target == 8000, "suggest mode must not change anything by itself")
    }

    @Test func automaticModeAppliesTheChangeAndReportsIt() throws {
        let fixture = try Fixture()
        let habit = try fixture.habit("Walk", rule: .healthQuantity(metric: .steps, target: 8000), mode: .automatic)
        try fixture.seed(habit, values: Array(repeating: 11000, count: 16), target: 8000)

        let result = fixture.engine.refresh()

        #expect(result.proposals.isEmpty, "an automatic change is not a pending suggestion")
        #expect(habit.rule.target > 8000)
        #expect(habit.lastGoalChangeAt == fixture.now)
        #expect(result.automaticChanges.count == 1)
        #expect(result.insights.contains { $0.kind == .goalChanged && $0.habitID == habit.id })
    }

    @Test func offModeNeverProposes() throws {
        let fixture = try Fixture()
        let habit = try fixture.habit("Walk", rule: .healthQuantity(metric: .steps, target: 8000), mode: .off)
        try fixture.seed(habit, values: Array(repeating: 11000, count: 16), target: 8000)

        let result = fixture.engine.refresh()

        #expect(result.proposals.isEmpty)
        #expect(habit.rule.target == 8000)
    }

    @Test func applyingAProposalUpdatesTheHabitAndClearsIt() throws {
        let fixture = try Fixture()
        let habit = try fixture.habit("Walk", rule: .healthQuantity(metric: .steps, target: 8000))
        try fixture.seed(habit, values: Array(repeating: 11000, count: 16), target: 8000)
        let proposal = try #require(fixture.engine.refresh().proposals.first)

        fixture.engine.apply(proposal)

        #expect(habit.rule.target == proposal.proposedTarget)
        #expect(fixture.engine.refresh().proposals.isEmpty)
        #expect(habit.lastGoalChangeAt == fixture.now)
    }

    @Test func dismissingStartsTheCooldown() throws {
        let fixture = try Fixture()
        let habit = try fixture.habit("Walk", rule: .healthQuantity(metric: .steps, target: 8000))
        try fixture.seed(habit, values: Array(repeating: 11000, count: 16), target: 8000)
        let proposal = try #require(fixture.engine.refresh().proposals.first)

        fixture.engine.dismiss(proposal)

        #expect(fixture.engine.refresh().proposals.isEmpty, "the same suggestion must not come back tomorrow")
        #expect(habit.lastProposalDismissedAt == fixture.now)
        #expect(habit.rule.target == 8000)
    }

    @Test func findsAPairingBetweenTwoHabits() throws {
        let fixture = try Fixture()
        let sleep = try fixture.habit("Sleep", rule: .healthSleep(minHours: 7), mode: .off)
        let read = try fixture.habit("Read", rule: .manual, mode: .off)
        // Alternating days: both succeed together, both fail together.
        let pattern = (0..<24).map { $0 % 2 == 0 ? 1.0 : 0.0 }
        try fixture.seed(sleep, values: pattern.map { $0 * 8 }, target: 7)
        try fixture.seed(read, values: pattern, target: 1)

        let result = fixture.engine.refresh()

        let pairing = try #require(result.insights.first { $0.kind == .pairing })
        #expect(pairing.primaryValue > pairing.secondaryValue)
        #expect([sleep.id, read.id].contains(pairing.habitID ?? UUID()))
    }

    @Test func noInsightsWithoutHabits() throws {
        let fixture = try Fixture()
        let result = fixture.engine.refresh()
        #expect(result.insights.isEmpty)
        #expect(result.proposals.isEmpty)
    }
}
