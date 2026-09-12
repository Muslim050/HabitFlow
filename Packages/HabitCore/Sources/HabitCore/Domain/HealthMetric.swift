import Foundation

/// Cumulative HealthKit quantities that a "≥ N per day" habit can be built on.
public enum HealthMetric: String, Codable, CaseIterable, Sendable, Hashable {
    case steps
    case activeEnergy
    case exerciseMinutes
    case distanceWalkRun
    case water

    public var displayName: String {
        switch self {
        case .steps: return "Steps"
        case .activeEnergy: return "Active energy"
        case .exerciseMinutes: return "Exercise minutes"
        case .distanceWalkRun: return "Walking + running distance"
        case .water: return "Water"
        }
    }

    public var unitLabel: String {
        switch self {
        case .steps: return "steps"
        case .activeEnergy: return "kcal"
        case .exerciseMinutes: return "min"
        case .distanceWalkRun: return "km"
        case .water: return "ml"
        }
    }

    public var defaultTarget: Double {
        switch self {
        case .steps: return 8_000
        case .activeEnergy: return 400
        case .exerciseMinutes: return 30
        case .distanceWalkRun: return 5
        case .water: return 2_000
        }
    }

    /// Increment used by steppers in the editor.
    public var stepIncrement: Double {
        switch self {
        case .steps: return 500
        case .activeEnergy: return 50
        case .exerciseMinutes: return 5
        case .distanceWalkRun: return 0.5
        case .water: return 250
        }
    }

    public var systemImage: String {
        switch self {
        case .steps: return "figure.walk"
        case .activeEnergy: return "flame"
        case .exerciseMinutes: return "figure.run"
        case .distanceWalkRun: return "point.topleft.down.to.point.bottomright.curvepath"
        case .water: return "drop"
        }
    }
}
