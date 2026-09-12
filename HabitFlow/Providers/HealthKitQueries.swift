import Foundation
import HealthKit
import HabitCore

/// Thin async wrappers over HealthKit query descriptors.
struct HealthKitQueries {
    let store: HKHealthStore

    /// Cumulative sum in the window. The statistics query merges overlapping iPhone/Watch samples like the Health app.
    func cumulativeSum(_ metric: HealthMetric, window: DateInterval) async throws -> Double {
        let type = HealthKitTypes.quantityType(for: metric)
        let predicate = HKQuery.predicateForSamples(withStart: window.start, end: window.end, options: .strictStartDate)
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: .cumulativeSum
        )
        let stats = try await descriptor.result(for: store)
        return stats?.sumQuantity()?.doubleValue(for: HealthKitTypes.unit(for: metric)) ?? 0
    }

    /// Asleep intervals overlapping the window (not yet clipped or merged).
    func asleepIntervals(window: DateInterval) async throws -> [DateInterval] {
        let predicate = HKQuery.predicateForSamples(withStart: window.start, end: window.end, options: [])
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HealthKitTypes.sleepType, predicate: predicate)],
            sortDescriptors: []
        )
        let samples = try await descriptor.result(for: store)
        let asleep = Set(HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue))
        return samples
            .filter { asleep.contains($0.value) }
            .map { DateInterval(start: $0.startDate, end: max($0.endDate, $0.startDate)) }
    }

    func mindfulIntervals(window: DateInterval) async throws -> [DateInterval] {
        let predicate = HKQuery.predicateForSamples(withStart: window.start, end: window.end, options: [])
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HealthKitTypes.mindfulType, predicate: predicate)],
            sortDescriptors: []
        )
        return try await descriptor.result(for: store)
            .map { DateInterval(start: $0.startDate, end: max($0.endDate, $0.startDate)) }
    }

    /// Workouts overlapping the window, optionally filtered by activity type.
    func workouts(window: DateInterval, activityRaw: UInt?) async throws -> [HKWorkout] {
        var predicates = [HKQuery.predicateForSamples(withStart: window.start, end: window.end, options: [])]
        if let activityRaw, let type = HKWorkoutActivityType(rawValue: activityRaw) {
            predicates.append(HKQuery.predicateForWorkouts(with: type))
        }
        let compound = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(compound)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        return try await descriptor.result(for: store)
    }
}
