import Foundation
import HealthKit
import HabitCore

/// Keeps one `HKObserverQuery` + background delivery per sample type in use.
/// Must be re-created on every launch (HealthKit does not persist observer queries).
@MainActor
final class HealthKitObserver {
    private let store: HKHealthStore
    private var queries: [HKSampleType: HKObserverQuery] = [:]

    init(store: HKHealthStore) {
        self.store = store
    }

    func start(types: Set<HKSampleType>, onChange: @escaping @Sendable @MainActor (HabitSourceKind) async -> Void) {
        // Drop observers for types no longer used.
        for (type, query) in queries where !types.contains(type) {
            store.stop(query)
            queries[type] = nil
            store.disableBackgroundDelivery(for: type) { _, error in
                if let error { Log.health.error("disableBackgroundDelivery: \(error.localizedDescription)") }
            }
        }

        for type in types where queries[type] == nil {
            let kind = HealthKitTypes.kind(for: type)
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
                if let error {
                    Log.health.error("Observer error for \(type.identifier): \(error.localizedDescription)")
                    completion()
                    return
                }
                Task { @MainActor in
                    if let kind { await onChange(kind) }
                    // Must always be called, otherwise HealthKit stops delivering after 3 misses.
                    completion()
                }
            }
            store.execute(query)
            queries[type] = query
            store.enableBackgroundDelivery(for: type, frequency: .immediate) { ok, error in
                if let error {
                    Log.health.error("enableBackgroundDelivery(\(type.identifier)): \(error.localizedDescription)")
                } else {
                    Log.health.info("Background delivery for \(type.identifier): \(ok)")
                }
            }
        }
    }

    func stopAll() {
        for (type, query) in queries {
            store.stop(query)
            store.disableBackgroundDelivery(for: type) { _, _ in }
        }
        queries.removeAll()
    }

    var observedTypes: Set<HKSampleType> { Set(queries.keys) }
}
