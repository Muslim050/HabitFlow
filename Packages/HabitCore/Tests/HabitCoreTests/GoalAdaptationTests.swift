import Foundation
import Testing
@testable import HabitCore

@Suite("GoalAdaptation")
struct GoalAdaptationTests {
    let steps = HabitRule.healthQuantity(metric: .steps, target: 8000)
    let now = Fixed.date(2026, 9, 12, 10)

    func samples(_ values: [Double], target: Double = 8000) -> [GoalAdaptation.DaySample] {
        values.map { GoalAdaptation.DaySample(value: $0, completed: $0 >= target) }
    }

    func proposal(_ values: [Double], rule: HabitRule? = nil, mode: GoalAdaptationMode = .suggest,
                  lastChange: Date? = nil, lastDismissed: Date? = nil) -> GoalProposal? {
        let rule = rule ?? steps
        return GoalAdaptation.proposal(
            habitID: UUID(), rule: rule, samples: samples(values, target: rule.target), mode: mode,
            lastChangeAt: lastChange, lastDismissedAt: lastDismissed, now: now, calendar: Fixed.calendar
        )
    }

    @Test func raisesGoalWhenConsistentlyExceeded() throws {
        let result = try #require(proposal(Array(repeating: 9600, count: 14)))
        #expect(result.direction == .increase)
        #expect(result.proposedTarget > 8000)
        #expect(result.proposedTarget <= 12000, "never more than +50% at once")
        #expect(result.proposedTarget.truncatingRemainder(dividingBy: 500) == 0, "snapped to the metric step")
        #expect(result.completionRate == 1)
        #expect(result.medianValue == 9600)
    }

    @Test func lowersGoalWhenConsistentlyMissed() throws {
        let result = try #require(proposal(Array(repeating: 5200, count: 14)))
        #expect(result.direction == .decrease)
        #expect(result.proposedTarget < 8000)
        #expect(result.proposedTarget >= 4000, "never less than -50% at once")
    }

    @Test func staysSilentInTheHealthyMiddle() {
        // Hits the goal most days without overshooting much: nothing to change.
        #expect(proposal(Array(repeating: 8200, count: 14)) == nil)
        // Mixed results, neither clearly good nor clearly bad.
        #expect(proposal([9000, 5000, 8200, 6000, 9500, 7000, 8100, 5500, 9000, 6500, 8000, 7200]) == nil)
    }

    @Test func needsEnoughHistory() {
        #expect(proposal(Array(repeating: 12000, count: 9)) == nil)
        #expect(proposal(Array(repeating: 12000, count: 10)) != nil)
    }

    @Test func respectsMode() {
        #expect(proposal(Array(repeating: 12000, count: 14), mode: .off) == nil)
        #expect(proposal(Array(repeating: 12000, count: 14), mode: .automatic) != nil)
    }

    @Test func respectsCooldownAfterChangeOrDismissal() {
        let recent = Fixed.calendar.date(byAdding: .day, value: -3, to: now)!
        let old = Fixed.calendar.date(byAdding: .day, value: -20, to: now)!
        #expect(proposal(Array(repeating: 12000, count: 14), lastChange: recent) == nil)
        #expect(proposal(Array(repeating: 12000, count: 14), lastDismissed: recent) == nil)
        #expect(proposal(Array(repeating: 12000, count: 14), lastChange: old) != nil)
    }

    @Test func usesOnlyTheLastFourteenDays() throws {
        // Two bad weeks followed by two great ones: only the recent window counts.
        let values = Array(repeating: 2000.0, count: 20) + Array(repeating: 11000.0, count: 14)
        let result = try #require(proposal(values))
        #expect(result.direction == .increase)
        #expect(result.sampleDays == 14)
    }

    @Test func manualHabitsHaveNoAdjustableGoal() {
        #expect(proposal(Array(repeating: 1, count: 14), rule: .manual) == nil)
    }

    @Test(arguments: [
        HabitRule.healthSleep(minHours: 7),
        HabitRule.healthMindful(minMinutes: 10),
        HabitRule.healthWorkout(activityRaw: nil, minMinutes: 30),
        HabitRule.geofence(latitude: 0, longitude: 0, radius: 150, minDwellMinutes: 40, placeName: "Gym"),
    ])
    func everyAdjustableRuleCanGrow(rule: HabitRule) throws {
        let values = Array(repeating: rule.target * 1.35, count: 14)
        let result = try #require(proposal(values, rule: rule))
        #expect(result.direction == .increase)
        #expect(result.proposedTarget > rule.target)
        #expect(rule.withTarget(result.proposedTarget)?.target == result.proposedTarget)
    }

    @Test func decreaseNeverGoesBelowTheFloor() throws {
        let rule = HabitRule.healthSleep(minHours: 5)
        let result = proposal(Array(repeating: 3.0, count: 14), rule: rule)
        if let result {
            #expect(result.proposedTarget >= rule.goalFloor)
        }
    }

    @Test func medianIgnoresOutliers() {
        #expect(GoalAdaptation.medianOf([1, 2, 3, 4, 100]) == 3)
        #expect(GoalAdaptation.medianOf([1, 2, 3, 4]) == 2.5)
        #expect(GoalAdaptation.medianOf([]) == 0)
    }

    @Test @MainActor func applyGoalStampsCooldownAndKeepsRuleShape() throws {
        let habit = Habit(name: "Gym", rule: .geofence(latitude: 1, longitude: 2, radius: 200, minDwellMinutes: 30, placeName: "Gym"))
        habit.applyGoal(45, at: now)
        guard case .geofence(let lat, let lon, let radius, let dwell, let place) = habit.rule else {
            Issue.record("rule shape changed"); return
        }
        #expect(lat == 1 && lon == 2 && radius == 200 && place == "Gym")
        #expect(dwell == 45)
        #expect(habit.lastGoalChangeAt == now)
    }
}
