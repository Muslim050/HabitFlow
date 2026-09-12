import Foundation

/// A source of automatic completion signals (HealthKit, CoreLocation, …).
/// Implementations live in the app target; the engine only sees this protocol.
@MainActor
public protocol HabitSourceProvider: AnyObject {
    var supportedKinds: Set<HabitSourceKind> { get }
    /// Whether the underlying system service exists on this device (e.g. `HKHealthStore.isHealthDataAvailable()`).
    var isAvailable: Bool { get }

    func requestAuthorization(for rules: [HabitRule]) async throws

    /// Observe the rule inside `window`. `habitID` lets providers look up their own per-habit state (visits).
    func snapshot(for rule: HabitRule, habitID: UUID, window: DateInterval, now: Date) async throws -> ProgressSnapshot

    /// Register system observers for the given habits. Await `onChange` when data of a kind may have changed;
    /// it resolves once the engine has re-evaluated, so background completion handlers can be called afterwards.
    func startObserving(habits: [(id: UUID, rule: HabitRule)], onChange: @escaping @Sendable @MainActor (HabitSourceKind) async -> Void)
    func stopObserving()
}

public enum ProviderError: Error, LocalizedError, Sendable {
    case unavailable(HabitSourceKind)
    case notAuthorized(HabitSourceKind)
    case unsupportedRule

    public var errorDescription: String? {
        switch self {
        case .unavailable(let kind): return "\(kind.rawValue) is not available on this device."
        case .notAuthorized(let kind): return "Permission for \(kind.rawValue) was not granted."
        case .unsupportedRule: return "This provider does not understand the rule."
        }
    }
}
