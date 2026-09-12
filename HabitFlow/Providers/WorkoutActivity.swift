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
        case .any: return "Any workout"
        case .running: return "Running"
        case .walking: return "Walking"
        case .cycling: return "Cycling"
        case .strength: return "Strength training"
        case .functionalStrength: return "Functional strength"
        case .yoga: return "Yoga"
        case .swimming: return "Swimming"
        case .hiking: return "Hiking"
        case .hiit: return "HIIT"
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
