import Foundation

/// Where a habit's completion signal comes from.
public enum HabitSourceKind: String, Codable, CaseIterable, Sendable, Hashable {
    case manual
    case healthQuantity
    case healthSleep
    case healthMindful
    case healthWorkout
    case geofence
    /// Reserved for v1.1 (needs the Family Controls entitlement). Not selectable in the MVP UI.
    case screenTime

    public var isAutomatic: Bool { self != .manual }

    /// Kinds the MVP lets the user pick.
    public static let selectable: [HabitSourceKind] = [
        .manual, .healthQuantity, .healthSleep, .healthMindful, .healthWorkout, .geofence,
    ]

    public var usesHealthKit: Bool {
        switch self {
        case .healthQuantity, .healthSleep, .healthMindful, .healthWorkout: return true
        default: return false
        }
    }
}
