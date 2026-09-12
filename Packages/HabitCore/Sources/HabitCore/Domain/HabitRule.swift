import Foundation

/// The rule that decides whether a habit counts as done for a logical day.
/// Stored on `Habit` as versioned JSON so new cases/fields are additive.
public enum HabitRule: Codable, Sendable, Hashable {
    case manual
    /// Cumulative HealthKit quantity in the day window must reach `target`.
    case healthQuantity(metric: HealthMetric, target: Double)
    /// Total asleep time in the night window must reach `minHours`.
    case healthSleep(minHours: Double)
    /// Total mindful-session minutes in the day window must reach `minMinutes`.
    case healthMindful(minMinutes: Double)
    /// Any single workout (optionally of `activityRaw` type) lasting at least `minMinutes`.
    case healthWorkout(activityRaw: UInt?, minMinutes: Double)
    /// A visit to the place with dwell time of at least `minDwellMinutes`.
    case geofence(latitude: Double, longitude: Double, radius: Double, minDwellMinutes: Double, placeName: String)

    public var kind: HabitSourceKind {
        switch self {
        case .manual: return .manual
        case .healthQuantity: return .healthQuantity
        case .healthSleep: return .healthSleep
        case .healthMindful: return .healthMindful
        case .healthWorkout: return .healthWorkout
        case .geofence: return .geofence
        }
    }

    /// Normalized numeric target used by progress rings. Manual habits target 1.
    public var target: Double {
        switch self {
        case .manual: return 1
        case .healthQuantity(_, let target): return target
        case .healthSleep(let minHours): return minHours
        case .healthMindful(let minMinutes): return minMinutes
        case .healthWorkout(_, let minMinutes): return minMinutes
        case .geofence(_, _, _, let minDwell, _): return minDwell
        }
    }

    /// Stable, non-localized unit key. Use `localizedUnit` for display.
    public var unitLabel: String {
        switch self {
        case .manual: return ""
        case .healthQuantity(let metric, _): return metric.unitLabel
        case .healthSleep: return "h"
        case .healthMindful, .healthWorkout, .geofence: return "min"
        }
    }

    public var localizedUnit: String { ValueFormatting.unit(unitLabel) }

    /// Same rule with a different numeric target. `nil` for rules that have no adjustable goal.
    public func withTarget(_ target: Double) -> HabitRule? {
        switch self {
        case .manual: return nil
        case .healthQuantity(let metric, _): return .healthQuantity(metric: metric, target: target)
        case .healthSleep: return .healthSleep(minHours: target)
        case .healthMindful: return .healthMindful(minMinutes: target)
        case .healthWorkout(let activityRaw, _): return .healthWorkout(activityRaw: activityRaw, minMinutes: target)
        case .geofence(let lat, let lon, let radius, _, let placeName):
            return .geofence(latitude: lat, longitude: lon, radius: radius, minDwellMinutes: target, placeName: placeName)
        }
    }

    /// Granularity used when proposing a new goal.
    public var goalStep: Double {
        switch self {
        case .manual: return 0
        case .healthQuantity(let metric, _): return metric.stepIncrement
        case .healthSleep: return 0.25
        case .healthMindful: return 1
        case .healthWorkout: return 5
        case .geofence: return 5
        }
    }

    /// Smallest sensible goal, so adaptation never proposes something meaningless.
    public var goalFloor: Double {
        switch self {
        case .manual: return 0
        case .healthQuantity(let metric, _): return metric.stepIncrement
        case .healthSleep: return 4
        case .healthMindful: return 1
        case .healthWorkout: return 5
        case .geofence: return 5
        }
    }

    /// Localized short label for the "auto-detected from …" badge.
    public var sourceLabel: String? {
        switch self {
        case .manual: return nil
        case .healthQuantity, .healthSleep, .healthMindful, .healthWorkout: return String(localized: "Health", bundle: .module)
        case .geofence: return String(localized: "Location", bundle: .module)
        }
    }

    public var systemImage: String {
        switch self {
        case .manual: return "hand.tap"
        case .healthQuantity(let metric, _): return metric.systemImage
        case .healthSleep: return "bed.double"
        case .healthMindful: return "brain.head.profile"
        case .healthWorkout: return "figure.strengthtraining.traditional"
        case .geofence: return "mappin.and.ellipse"
        }
    }
}

/// Versioned envelope so the stored JSON can evolve.
struct HabitRuleEnvelope: Codable {
    static let currentVersion = 1
    var v: Int
    var rule: HabitRule
}

public enum HabitRuleCoding {
    public static func encode(_ rule: HabitRule) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(HabitRuleEnvelope(v: HabitRuleEnvelope.currentVersion, rule: rule))
    }

    /// Falls back to `.manual` for empty or unreadable data so a corrupt row never crashes the app.
    public static func decode(_ data: Data) -> HabitRule {
        guard !data.isEmpty else { return .manual }
        return (try? JSONDecoder().decode(HabitRuleEnvelope.self, from: data))?.rule ?? .manual
    }
}
