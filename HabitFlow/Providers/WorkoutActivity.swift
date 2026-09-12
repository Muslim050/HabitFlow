import Foundation
import HealthKit

/// The subset of `HKWorkoutActivityType` offered in the editor. Raw values are HealthKit's.
enum WorkoutActivity: UInt, CaseIterable, Identifiable {
    case any = 0
    case running = 37
    case walking = 52
    case cycling = 13
    case strength = 50
    case functionalStrength = 20
    case yoga = 63
    case swimming = 46
    case hiking = 24
    case hiit = 62

    var id: UInt { rawValue }

    var displayName: String {
        switch self {
        case .any: return String(localized: "Any workout")
        case .running: return String(localized: "Running")
        case .walking: return String(localized: "Walking")
        case .cycling: return String(localized: "Cycling")
        case .strength: return String(localized: "Strength training")
        case .functionalStrength: return String(localized: "Functional strength")
        case .yoga: return String(localized: "Yoga")
        case .swimming: return String(localized: "Swimming")
        case .hiking: return String(localized: "Hiking")
        case .hiit: return String(localized: "HIIT")
        }
    }

    var healthKitType: HKWorkoutActivityType? {
        self == .any ? nil : HKWorkoutActivityType(rawValue: rawValue)
    }

    /// `nil` raw value in a rule means "any".
    static func from(raw: UInt?) -> WorkoutActivity {
        guard let raw, let activity = WorkoutActivity(rawValue: raw) else { return .any }
        return activity
    }

    static func name(forRaw raw: UInt?) -> String {
        from(raw: raw).displayName
    }
}
