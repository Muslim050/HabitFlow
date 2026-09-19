import Foundation

/// When each source last actually did something.
///
/// The failure mode of an automatic tracker is silent death: background delivery stops, a region
/// never registers, the refresh task is not granted time for a week — and every one of those
/// looks exactly like "no data today" from the outside. These timestamps are the only way to tell
/// them apart, and none of it can be observed on the Simulator.
public struct SourceReport: Codable, Sendable, Equatable {
    /// The source pushed a change at us (an observer fired, a region was crossed).
    public var lastDeliveryAt: Date?
    /// We asked the source for a value and it answered.
    public var lastReadAt: Date?
    /// What that answer was, so "answered with zero" is distinguishable from "did not answer".
    public var lastValue: Double?
    public var lastError: String?
    public var lastErrorAt: Date?

    public init() {}

    public var hasEverDelivered: Bool { lastDeliveryAt != nil }
    public var hasEverRead: Bool { lastReadAt != nil }
}

/// Small append-only telemetry kept in the App Group defaults, so the widget process and any
/// background wake write to the same place the app reads from.
public enum SourceHealth {
    public static let key = "sourceHealth"
    public static let backgroundRunKey = "lastBackgroundRefreshAt"
    public static let backgroundOutcomeKey = "lastBackgroundRefreshOutcome"

    // MARK: Reading

    public static func report(for kind: HabitSourceKind, defaults: UserDefaults = AppSettings.store) -> SourceReport {
        all(defaults: defaults)[kind.rawValue] ?? SourceReport()
    }

    public static func all(defaults: UserDefaults = AppSettings.store) -> [String: SourceReport] {
        guard let data = defaults.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: SourceReport].self, from: data)) ?? [:]
    }

    public static var lastBackgroundRefreshAt: Date? {
        AppSettings.store.object(forKey: backgroundRunKey) as? Date
    }

    public static var lastBackgroundRefreshOutcome: String? {
        AppSettings.store.string(forKey: backgroundOutcomeKey)
    }

    // MARK: Writing

    public static func recordDelivery(_ kind: HabitSourceKind, at date: Date = Date(),
                                      defaults: UserDefaults = AppSettings.store) {
        update(kind, defaults: defaults) { $0.lastDeliveryAt = date }
    }

    public static func recordRead(_ kind: HabitSourceKind, value: Double, at date: Date = Date(),
                                  defaults: UserDefaults = AppSettings.store) {
        update(kind, defaults: defaults) {
            $0.lastReadAt = date
            $0.lastValue = value
            $0.lastError = nil
        }
    }

    public static func recordError(_ kind: HabitSourceKind, _ message: String, at date: Date = Date(),
                                   defaults: UserDefaults = AppSettings.store) {
        update(kind, defaults: defaults) {
            $0.lastError = message
            $0.lastErrorAt = date
        }
    }

    public static func recordBackgroundRefresh(outcome: String, at date: Date = Date(),
                                               defaults: UserDefaults = AppSettings.store) {
        defaults.set(date, forKey: backgroundRunKey)
        defaults.set(outcome, forKey: backgroundOutcomeKey)
    }

    /// Only used by the tests and by a deliberate reset in the diagnostics screen.
    public static func reset(defaults: UserDefaults = AppSettings.store) {
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: backgroundRunKey)
        defaults.removeObject(forKey: backgroundOutcomeKey)
    }

    private static func update(_ kind: HabitSourceKind, defaults: UserDefaults,
                               _ change: (inout SourceReport) -> Void) {
        var reports = all(defaults: defaults)
        var report = reports[kind.rawValue] ?? SourceReport()
        change(&report)
        reports[kind.rawValue] = report
        defaults.set(try? JSONEncoder().encode(reports), forKey: key)
    }
}
