import Foundation
import HealthKit
import Testing
import HabitCore
@testable import HabitFlow

@Suite("App smoke")
struct AppSmokeTests {
    @Test(arguments: HealthMetric.allCases)
    func everyMetricMapsToAHealthKitType(metric: HealthMetric) {
        let type = HealthKitTypes.quantityType(for: metric)
        let unit = HealthKitTypes.unit(for: metric)
        #expect(type.is(compatibleWith: unit), "\(metric) unit must match its quantity type")
    }

    @Test func rulesMapToSampleTypes() {
        #expect(HealthKitTypes.sampleTypes(for: .manual).isEmpty)
        #expect(HealthKitTypes.sampleTypes(for: .healthSleep(minHours: 7)) == [HealthKitTypes.sleepType])
        #expect(HealthKitTypes.sampleTypes(for: .healthWorkout(activityRaw: nil, minMinutes: 30)) == [HealthKitTypes.workoutType])
        #expect(HealthKitTypes.kind(for: HealthKitTypes.quantityType(for: .steps)) == .healthQuantity)
        #expect(HealthKitTypes.kind(for: HealthKitTypes.workoutType) == .healthWorkout)
        #expect(HealthKitTypes.allReadTypes.count == HealthMetric.allCases.count + 3)
    }

    @Test func workoutActivityRoundTrip() {
        #expect(WorkoutActivity.from(raw: nil) == .any)
        #expect(WorkoutActivity.from(raw: 37) == .running)
        #expect(WorkoutActivity.running.healthKitType == .running)
        #expect(WorkoutActivity.any.healthKitType == nil)
    }

    @Test func autoCompletedNotificationContent() {
        let event = CompletionEvent(
            habitID: UUID(), habitName: "Walk", emoji: "🚶", dayKey: DayKey(raw: "2026-09-12"),
            value: 8214, target: 8000, unitLabel: "steps", sourceLabel: "Health", reason: .healthKitDelivery
        )
        let content = NotificationService.autoCompletedContent(for: event)
        #expect(content.title.contains("Walk"))
        #expect(content.body.contains("8 000") || content.body.contains("8,000"))
        #expect(content.body.hasSuffix("from Health"))
        #expect(content.threadIdentifier == "auto-2026-09-12")
    }

    @Test func nudgeContentListsUnfinished() {
        let content = NotificationService.nudgeContent(unfinished: ["📚 Read", "💧 Water"])
        #expect(content.title == "2 habits left today")
        #expect(content.body == "📚 Read · 💧 Water")
        #expect(NotificationService.nudgeIdentifier(for: DayKey(raw: "2026-09-12")) == "nudge-2026-09-12")
    }

    @Test func geofenceRadiusIsClamped() {
        #expect(LocationProvider.clampedRadius(20) == 100)
        #expect(LocationProvider.clampedRadius(5000) == 500)
        #expect(LocationProvider.clampedRadius(250) == 250)
    }

    @Test @MainActor func sharedEnvironmentBoots() {
        let env = AppEnvironment.shared
        #expect(env.registry.provider(for: .healthQuantity) != nil)
        #expect(env.registry.provider(for: .geofence) != nil)
        #expect(env.registry.provider(for: .manual) == nil)
    }
}
