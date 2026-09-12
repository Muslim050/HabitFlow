import Foundation
import HealthKit
import HabitCore

@MainActor
final class HealthKitProvider: HabitSourceProvider {
    let store = HKHealthStore()
    private lazy var queries = HealthKitQueries(store: store)
    private lazy var observer = HealthKitObserver(store: store)

    let supportedKinds: Set<HabitSourceKind> = [.healthQuantity, .healthSleep, .healthMindful, .healthWorkout]

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // MARK: Authorization

    func requestAuthorization(for rules: [HabitRule]) async throws {
        let types = rules.reduce(into: Set<HKSampleType>()) { $0.formUnion(HealthKitTypes.sampleTypes(for: $1)) }
        try await requestReadAuthorization(types: types)
    }

    /// Asks for every type at once; used by onboarding so the sheet appears a single time.
    func requestAllReadAuthorization() async throws {
        try await requestReadAuthorization(types: HealthKitTypes.allReadTypes)
    }

    private func requestReadAuthorization(types: Set<HKSampleType>) async throws {
        guard isAvailable, !types.isEmpty else { return }
        try await store.requestAuthorization(toShare: [], read: Set(types.map { $0 as HKObjectType }))
        AppSettings.shared.healthAuthorizationRequested = true
    }

    // MARK: Snapshot

    func snapshot(for rule: HabitRule, habitID: UUID, window: DateInterval, now: Date) async throws -> ProgressSnapshot {
        guard isAvailable else { throw ProviderError.unavailable(rule.kind) }
        switch rule {
        case .healthQuantity(let metric, let target):
            let value = try await queries.cumulativeSum(metric, window: window)
            return ProgressSnapshot(value: value, target: target, observedAt: now)

        case .healthSleep(let minHours):
            let intervals = try await queries.asleepIntervals(window: window)
            let hours = IntervalMath.totalDuration(of: intervals, clippedTo: window) / 3600
            return ProgressSnapshot(value: (hours * 10).rounded() / 10, target: minHours, observedAt: now)

        case .healthMindful(let minMinutes):
            let intervals = try await queries.mindfulIntervals(window: window)
            let minutes = IntervalMath.totalDuration(of: intervals, clippedTo: window) / 60
            return ProgressSnapshot(value: minutes.rounded(), target: minMinutes, observedAt: now)

        case .healthWorkout(let activityRaw, let minMinutes):
            let workouts = try await queries.workouts(window: window, activityRaw: activityRaw)
            let longest = workouts.map { $0.duration / 60 }.max() ?? 0
            let detail = workouts.isEmpty ? "No workout yet" : "\(workouts.count) workout(s), longest \(Int(longest)) min"
            return ProgressSnapshot(value: longest.rounded(), target: minMinutes, observedAt: now, detail: detail)

        case .manual, .geofence:
            throw ProviderError.unsupportedRule
        }
    }

    // MARK: Observing

    func startObserving(habits: [(id: UUID, rule: HabitRule)], onChange: @escaping @MainActor (HabitSourceKind) async -> Void) {
        guard isAvailable else { return }
        let types = habits.reduce(into: Set<HKSampleType>()) { $0.formUnion(HealthKitTypes.sampleTypes(for: $1.rule)) }
        observer.start(types: types, onChange: onChange)
    }

    func stopObserving() {
        observer.stopAll()
    }
}
