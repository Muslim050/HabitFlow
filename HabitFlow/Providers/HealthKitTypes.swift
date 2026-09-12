import Foundation
import HealthKit
import HabitCore

/// Maps domain rules to HealthKit types/units. Kept pure so it can be unit-tested.
enum HealthKitTypes {
    static func quantityType(for metric: HealthMetric) -> HKQuantityType {
        switch metric {
        case .steps: return HKQuantityType(.stepCount)
        case .activeEnergy: return HKQuantityType(.activeEnergyBurned)
        case .exerciseMinutes: return HKQuantityType(.appleExerciseTime)
        case .distanceWalkRun: return HKQuantityType(.distanceWalkingRunning)
        case .water: return HKQuantityType(.dietaryWater)
        }
    }

    static func unit(for metric: HealthMetric) -> HKUnit {
        switch metric {
        case .steps: return .count()
        case .activeEnergy: return .kilocalorie()
        case .exerciseMinutes: return .minute()
        case .distanceWalkRun: return .meterUnit(with: .kilo)
        case .water: return .literUnit(with: .milli)
        }
    }

    static var sleepType: HKCategoryType { HKCategoryType(.sleepAnalysis) }
    static var mindfulType: HKCategoryType { HKCategoryType(.mindfulSession) }
    static var workoutType: HKWorkoutType { HKObjectType.workoutType() }

    /// Sample types a rule needs to read.
    static func sampleTypes(for rule: HabitRule) -> Set<HKSampleType> {
        switch rule {
        case .manual, .geofence: return []
        case .healthQuantity(let metric, _): return [quantityType(for: metric)]
        case .healthSleep: return [sleepType]
        case .healthMindful: return [mindfulType]
        case .healthWorkout: return [workoutType]
        }
    }

    /// Every read type the app can ever need (used by onboarding so the permission sheet appears once).
    static var allReadTypes: Set<HKSampleType> {
        var set = Set<HKSampleType>(HealthMetric.allCases.map { quantityType(for: $0) })
        set.insert(sleepType)
        set.insert(mindfulType)
        set.insert(workoutType)
        return set
    }

    /// Which habit kind an observed sample type feeds.
    static func kind(for sampleType: HKSampleType) -> HabitSourceKind? {
        if sampleType is HKQuantityType { return .healthQuantity }
        if sampleType == sleepType { return .healthSleep }
        if sampleType == mindfulType { return .healthMindful }
        if sampleType is HKWorkoutType { return .healthWorkout }
        return nil
    }
}
