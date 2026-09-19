import Foundation
import Testing
@testable import HabitCore

@Suite("HabitRule coding")
struct HabitRuleCodingTests {
    static let rules: [HabitRule] = [
        .manual,
        .healthQuantity(metric: .steps, target: 8000),
        .healthSleep(minHours: 7.5),
        .healthMindful(minMinutes: 10),
        .healthWorkout(activityRaw: nil, minMinutes: 30),
        .healthWorkout(activityRaw: 37, minMinutes: 45),
        .geofence(latitude: 55.75, longitude: 37.61, radius: 150, minDwellMinutes: 40, placeName: "Gym"),
    ]

    @Test(arguments: rules)
    func roundTrips(rule: HabitRule) throws {
        let data = try HabitRuleCoding.encode(rule)
        #expect(HabitRuleCoding.decode(data) == rule)
    }

    @Test func envelopeIsVersioned() throws {
        let data = try HabitRuleCoding.encode(.healthSleep(minHours: 8))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["v"] as? Int == 1)
    }

    @Test func corruptDataFallsBackToManual() {
        #expect(HabitRuleCoding.decode(Data()) == .manual)
        #expect(HabitRuleCoding.decode(Data("{not json".utf8)) == .manual)
    }

    @Test func derivedProperties() {
        let steps = HabitRule.healthQuantity(metric: .steps, target: 8000)
        #expect(steps.kind == .healthQuantity)
        #expect(steps.target == 8000)
        #expect(steps.unitLabel == "steps")
        #expect(steps.sourceLabel == "Health")
        #expect(HabitRule.manual.sourceLabel == nil)
        #expect(HabitRule.geofence(latitude: 0, longitude: 0, radius: 100, minDwellMinutes: 30, placeName: "x").kind == .geofence)
    }

    @Test func habitStoresRule() {
        let habit = Habit(name: "Walk", rule: .healthQuantity(metric: .steps, target: 8000))
        #expect(habit.kind == .healthQuantity)
        #expect(habit.isAutomatic)
        habit.rule = .manual
        #expect(habit.kind == .manual)
        #expect(!habit.isAutomatic)
    }

    /// Rows written before flexible schedules existed carry only the weekday mask, and the
    /// getter has to read them without inventing anything.
    @Test func legacyWeekdayMaskStillReads() {
        let habit = Habit(name: "x")
        habit.scheduleData = Data()
        habit.scheduleMask = 0b000_0010          // Monday only
        #expect(habit.schedule == .weekdays(mask: 0b000_0010))

        habit.scheduleMask = HabitSchedule.everyDayMask
        #expect(habit.schedule == .everyDay, "a full mask is every day, not a seven-bit special case")
    }

    @Test func writingAScheduleKeepsTheLegacyMaskInStep() {
        let habit = Habit(name: "x")
        habit.schedule = .weekdays(mask: 0b011_1110)
        #expect(habit.scheduleMask == 0b011_1110)

        habit.schedule = .timesPerWeek(count: 3)
        #expect(habit.scheduleMask == HabitSchedule.everyDayMask, "any day will do, so every bit is set")
        #expect(habit.schedule == .timesPerWeek(count: 3), "the JSON wins over the mask")
    }
}
