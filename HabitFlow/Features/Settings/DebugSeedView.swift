#if DEBUG
import HealthKit
import SwiftUI
import HabitCore

/// Writes sample data into Health so automatic habits can be exercised in the Simulator.
struct DebugSeedView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var message = ""

    var body: some View {
        List {
            Section("Write to Health") {
                Button("Add 9 000 steps (today)") { seed { try await seedQuantity(.steps, value: 9000) } }
                Button("Add 450 kcal active energy") { seed { try await seedQuantity(.activeEnergy, value: 450) } }
                Button("Add 750 ml water") { seed { try await seedQuantity(.water, value: 750) } }
                Button("Add 7.5 h sleep (last night)") { seed { try await seedSleep(hours: 7.5) } }
                Button("Add 12 mindful minutes") { seed { try await seedMindful(minutes: 12) } }
                Button("Add 35 min running workout") { seed { try await seedWorkout(minutes: 35) } }
            }
            Section("Then") {
                Button("Run auto-tracking now") { Task { await env.engine.evaluateAll(reason: .manualRefresh) } }
            }
            if !message.isEmpty {
                Section { Text(message).font(.footnote) }
            }
        }
        .navigationTitle("Seed Health data")
    }

    private var store: HKHealthStore { env.healthKit.store }

    private func seed(_ work: @escaping () async throws -> Void) {
        Task {
            do {
                try await work()
                message = "Saved. Run auto-tracking to see the effect."
                await env.engine.evaluateAll(reason: .manualRefresh)
            } catch {
                message = "Failed: \(error.localizedDescription)"
            }
        }
    }

    private func authorizeShare(_ types: Set<HKSampleType>) async throws {
        try await store.requestAuthorization(toShare: types, read: Set(types.map { $0 as HKObjectType }))
    }

    private func seedQuantity(_ metric: HealthMetric, value: Double) async throws {
        let type = HealthKitTypes.quantityType(for: metric)
        try await authorizeShare([type])
        let end = Date()
        let sample = HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: HealthKitTypes.unit(for: metric), doubleValue: value),
            start: end.addingTimeInterval(-1800),
            end: end
        )
        try await store.save(sample)
    }

    private func seedSleep(hours: Double) async throws {
        let type = HealthKitTypes.sleepType
        try await authorizeShare([type])
        let dayStart = env.settings.dayCalendar.dayStart(for: env.currentDayKey)
        let end = dayStart.addingTimeInterval(2.5 * 3600)   // 06:30 for a 04:00 day start
        let start = end.addingTimeInterval(-hours * 3600)   // crosses midnight
        let sample = HKCategorySample(
            type: type,
            value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            start: start,
            end: end
        )
        try await store.save(sample)
    }

    private func seedMindful(minutes: Double) async throws {
        let type = HealthKitTypes.mindfulType
        try await authorizeShare([type])
        let end = Date()
        let sample = HKCategorySample(type: type, value: HKCategoryValue.notApplicable.rawValue,
                                      start: end.addingTimeInterval(-minutes * 60), end: end)
        try await store.save(sample)
    }

    private func seedWorkout(minutes: Double) async throws {
        try await authorizeShare([HealthKitTypes.workoutType])
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        let end = Date()
        let start = end.addingTimeInterval(-minutes * 60)
        try await builder.beginCollection(at: start)
        try await builder.endCollection(at: end)
        _ = try await builder.finishWorkout()
    }
}
#endif
