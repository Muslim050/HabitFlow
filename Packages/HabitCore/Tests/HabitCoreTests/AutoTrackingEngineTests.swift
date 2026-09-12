import Foundation
import Testing
@testable import HabitCore

@Suite("AutoTrackingEngine")
@MainActor
struct AutoTrackingEngineTests {
    let steps = HabitRule.healthQuantity(metric: .steps, target: 8000)

    @Test func completesWhenSatisfied() async throws {
        let env = try TestEnv()
        let habit = try env.addHabit("Walk", rule: steps)
        env.health.values[habit.id] = 9000
        var events: [CompletionEvent] = []
        env.engine.onAutoCompleted = { events.append($0) }

        let summary = await env.engine.evaluateAll(reason: .foreground)

        let log = try #require(try env.log(habit))
        #expect(log.isCompleted)
        #expect(log.completionSource == .auto)
        #expect(log.progressValue == 9000)
        #expect(log.targetValue == 8000)
        #expect(summary.completions.count == 1)
        #expect(events.first?.habitName == "Walk")
        #expect(events.first?.sourceLabel == "Health")
    }

    @Test func isIdempotent() async throws {
        let env = try TestEnv()
        let habit = try env.addHabit("Walk", rule: steps)
        env.health.values[habit.id] = 9000
        await env.engine.evaluateAll(reason: .foreground)
        let second = await env.engine.evaluateAll(reason: .timer)
        #expect(second.completions.isEmpty)
        let logs = try env.repository.logs(habitID: habit.id, from: env.today, to: env.today)
        #expect(logs.count == 1)
    }

    @Test func storesPartialProgress() async throws {
        let env = try TestEnv()
        let habit = try env.addHabit("Walk", rule: steps)
        env.health.values[habit.id] = 6231
        await env.engine.evaluateAll(reason: .foreground)
        let log = try #require(try env.log(habit))
        #expect(!log.isCompleted)
        #expect(log.progressValue == 6231)
        #expect(abs(log.ratio - 6231.0 / 8000.0) < 0.0001)
    }

    @Test func manualOverrideWins() async throws {
        let env = try TestEnv()
        let habit = try env.addHabit("Walk", rule: steps)
        try env.engine.setManualCompletion(habitID: habit.id, completed: false)
        env.health.values[habit.id] = 12000
        let summary = await env.engine.evaluateAll(reason: .foreground)
        let log = try #require(try env.log(habit))
        #expect(!log.isCompleted)
        #expect(log.completionSource == .manualOverride)
        #expect(log.progressValue == 12000, "ring stays live even when overridden")
        #expect(summary.completions.isEmpty)

        try await env.engine.clearOverride(habitID: habit.id)
        let cleared = try #require(try env.log(habit))
        #expect(cleared.isCompleted)
        #expect(cleared.completionSource == .auto)
    }

    @Test func manualMarkDoneOnAutoHabit() async throws {
        let env = try TestEnv()
        let habit = try env.addHabit("Walk", rule: steps)
        try env.engine.setManualCompletion(habitID: habit.id, completed: true)
        env.health.values[habit.id] = 100
        await env.engine.evaluateAll(reason: .foreground)
        let log = try #require(try env.log(habit))
        #expect(log.isCompleted)
        #expect(log.completionSource == .manualOverride)
    }

    @Test func uncompletesWhenDataDisappearsToday() async throws {
        let env = try TestEnv()
        let habit = try env.addHabit("Walk", rule: steps)
        env.health.values[habit.id] = 9000
        await env.engine.evaluateAll(reason: .foreground)
        env.health.values[habit.id] = 100
        await env.engine.evaluateAll(reason: .healthKitDelivery)
        let log = try #require(try env.log(habit))
        #expect(!log.isCompleted)
        #expect(log.completionSource == .unset)
    }

    @Test func skipsUnscheduledDay() async throws {
        let env = try TestEnv()  // 2026-09-12 is a Saturday (weekday 7)
        let weekdaysOnly = 0b011_1110
        let habit = try env.addHabit("Walk", rule: steps, scheduleMask: weekdaysOnly)
        env.health.values[habit.id] = 9000
        await env.engine.evaluateAll(reason: .foreground)
        #expect(try env.log(habit) == nil)
        #expect(env.health.snapshotCalls == 0)
    }

    @Test func ignoresManualHabits() async throws {
        let env = try TestEnv()
        let habit = try env.addHabit("Read", rule: .manual)
        await env.engine.evaluateAll(reason: .foreground)
        #expect(try env.log(habit) == nil)
        try env.engine.setManualCompletion(habitID: habit.id, completed: true)
        let log = try #require(try env.log(habit))
        #expect(log.isCompleted)
        #expect(log.completionSource == .manual)
        try env.engine.setManualCompletion(habitID: habit.id, completed: false)
        #expect(try env.log(habit)?.isCompleted == false)
        #expect(try env.log(habit)?.completionSource == .unset)
    }

    @Test func dayRolloverCreatesNewLog() async throws {
        let env = try TestEnv()
        let habit = try env.addHabit("Walk", rule: steps)
        env.health.values[habit.id] = 9000
        await env.engine.evaluateAll(reason: .foreground)
        let firstDay = env.today
        env.clock.advance(by: 24 * 3600)
        env.health.values[habit.id] = 500
        await env.engine.evaluateAll(reason: .dayRollover)
        let logs = try env.repository.logs(habitID: habit.id, from: firstDay, to: env.today)
        #expect(logs.count == 2)
        #expect(logs[0].isCompleted)
        #expect(!logs[1].isCompleted)
    }

    @Test func providerErrorIsRecorded() async throws {
        let env = try TestEnv()
        let habit = try env.addHabit("Walk", rule: steps)
        env.health.error = TestError()
        let summary = await env.engine.evaluateAll(reason: .foreground)
        #expect(summary.failures[habit.id] != nil)
        #expect(try env.log(habit)?.isCompleted == false)
    }

    @Test func sleepUsesNightWindow() async throws {
        let env = try TestEnv()
        let habit = try env.addHabit("Sleep", rule: .healthSleep(minHours: 7))
        env.health.values[habit.id] = 7.5
        await env.engine.evaluateAll(reason: .foreground)
        let window = try #require(env.health.lastWindow)
        #expect(window == env.engine.dayCalendar.sleepWindow(for: env.today))
        #expect(try env.log(habit)?.isCompleted == true)
    }

    @Test func evaluatesOnlyRequestedKinds() async throws {
        let env = try TestEnv()
        let walk = try env.addHabit("Walk", rule: steps)
        let gym = try env.addHabit("Gym", rule: .geofence(latitude: 0, longitude: 0, radius: 100, minDwellMinutes: 30, placeName: "Gym"))
        env.health.values[walk.id] = 9000
        env.location.values[gym.id] = 60
        await env.engine.evaluate(kinds: [.geofence], reason: .locationEvent)
        #expect(try env.log(gym)?.isCompleted == true)
        #expect(try env.log(walk) == nil)
        #expect(env.health.snapshotCalls == 0)
    }

    @Test func archivedHabitsAreSkipped() async throws {
        let env = try TestEnv()
        let habit = try env.addHabit("Walk", rule: steps)
        habit.archivedAt = env.clock.now
        try env.repository.save()
        env.health.values[habit.id] = 9000
        await env.engine.evaluateAll(reason: .foreground)
        #expect(try env.log(habit) == nil)
    }

    @Test func finalizeDayClosesStaleVisits() async throws {
        let env = try TestEnv()
        let gym = try env.addHabit("Gym", rule: .geofence(latitude: 0, longitude: 0, radius: 100, minDwellMinutes: 30, placeName: "Gym"))
        let stale = GeofenceVisit(habitID: gym.id, enteredAt: env.clock.now.addingTimeInterval(-30 * 3600))
        env.repository.insert(stale)
        try env.repository.save()
        await env.engine.finalizeDay(env.engine.dayCalendar.key(byAdding: -1, to: env.today))
        #expect(stale.exitedAt != nil)
        #expect(try env.repository.openVisit(habitID: gym.id) == nil)
    }

    @Test func didEvaluateFiresAndRecordsRunTime() async throws {
        let env = try TestEnv()
        var fired = 0
        env.engine.onDidEvaluate = { _ in fired += 1 }
        await env.engine.evaluateAll(reason: .foreground)
        #expect(fired == 1)
        #expect(env.settings.lastEngineRunAt == env.clock.now)
    }
}
