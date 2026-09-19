import Foundation
import SwiftData
import Testing
@testable import HabitCore

@Suite("HabitMatrix")
@MainActor
struct HabitMatrixTests {
    @MainActor
    struct Fixture {
        let container: ModelContainer
        let repository: SwiftDataHabitRepository
        let calendar: DayCalendar
        let today: DayKey

        init() throws {
            container = try ModelContainerFactory.inMemory()
            repository = SwiftDataHabitRepository(container: container)
            calendar = DayCalendar(dayStartHour: 4, calendar: Fixed.calendar)
            today = calendar.dayKey(for: Fixed.date(2026, 9, 12, 10))   // Saturday
        }

        @discardableResult
        func habit(_ name: String, createdDaysAgo: Int = 60,
                   schedule: HabitSchedule = .everyDay, colorHex: String = "#4F8EF7") throws -> Habit {
            let created = calendar.dayStart(for: calendar.key(byAdding: -createdDaysAgo, to: today))
            let habit = Habit(name: name, emoji: "✅", colorHex: colorHex,
                              rule: .healthQuantity(metric: .steps, target: 8000),
                              schedule: schedule, createdAt: created)
            repository.insert(habit)
            try repository.save()
            return habit
        }

        func log(_ habit: Habit, daysAgo: Int, progress: Double, completed: Bool) throws {
            let key = calendar.key(byAdding: -daysAgo, to: today)
            let log = try repository.fetchOrCreateLog(habitID: habit.id, dayKey: key,
                                                      dayStart: calendar.dayStart(for: key), target: 8000)
            log.progressValue = progress
            log.targetValue = 8000
            log.isCompleted = completed
            try repository.save()
        }

        func build(days: Int) throws -> HabitMatrix {
            HabitMatrix.build(habits: try repository.activeHabits(),
                              logs: try repository.logs(from: calendar.key(byAdding: -90, to: today), to: today),
                              calendar: calendar, today: today, days: days)
        }
    }

    @Test func shapeMatchesHabitsAndDays() throws {
        let fixture = try Fixture()
        try fixture.habit("Walk")
        try fixture.habit("Read")

        let week = try fixture.build(days: 7)
        #expect(week.days.count == 7)
        #expect(week.days.last == fixture.today)
        #expect(week.rows.count == 2)
        #expect(week.rows.allSatisfy { $0.states.count == 7 })

        let fortnight = try fixture.build(days: 14)
        #expect(fortnight.days.count == 14)
        #expect(fortnight.rows.allSatisfy { $0.states.count == 14 })
    }

    @Test func statesCoverDonePartialAndMissed() throws {
        let fixture = try Fixture()
        let walk = try fixture.habit("Walk")
        try fixture.log(walk, daysAgo: 1, progress: 9000, completed: true)
        try fixture.log(walk, daysAgo: 2, progress: 4000, completed: false)
        // day 3 has no log at all

        let row = try #require(try fixture.build(days: 7).rows.first)
        #expect(row.states[6 - 1] == .done)        // yesterday
        #expect(row.states[6 - 2] == .partial(0.5))
        #expect(row.states[6 - 3] == .missed)
    }

    @Test func unscheduledAndPreCreationDaysAreOff() throws {
        let fixture = try Fixture()
        // Weekdays only; today (Saturday) is not due.
        let gym = try fixture.habit("Gym", createdDaysAgo: 3, schedule: .weekdays(mask: 0b011_1110))
        let row = try #require(try fixture.build(days: 7).rows.first)

        #expect(row.states.last == .off, "Saturday is not scheduled")
        #expect(row.states.first == .off, "that day is older than the habit")
        #expect(row.scheduledCount < 7)
        _ = gym
    }

    @Test func countsOnlyCountDueDays() throws {
        let fixture = try Fixture()
        let walk = try fixture.habit("Walk", schedule: .weekdays(mask: 0b011_1110))   // weekdays
        try fixture.log(walk, daysAgo: 1, progress: 9000, completed: true)   // Friday
        try fixture.log(walk, daysAgo: 2, progress: 9000, completed: true)   // Thursday

        let row = try #require(try fixture.build(days: 7).rows.first)
        #expect(row.doneCount == 2)
        #expect(row.scheduledCount == 5, "a week holds five weekdays")
    }

    @Test func aTickOnAnOffDayStillShowsAsDone() throws {
        let fixture = try Fixture()
        let gym = try fixture.habit("Gym", schedule: .weekdays(mask: 0b011_1110))
        try fixture.log(gym, daysAgo: 0, progress: 1, completed: true)   // Saturday, not due

        let row = try #require(try fixture.build(days: 7).rows.first)
        #expect(row.states.last == .done)
        #expect(row.doneCount == 1)
    }

    @Test func rowsCarryHabitIdentity() throws {
        let fixture = try Fixture()
        let walk = try fixture.habit("Walk", colorHex: "#FF9500")
        let row = try #require(try fixture.build(days: 7).rows.first)
        #expect(row.id == walk.id)
        #expect(row.name == "Walk")
        #expect(row.colorHex == "#FF9500")
    }

    @Test func emptyInputsAreSafe() throws {
        let fixture = try Fixture()
        #expect(try fixture.build(days: 7) == .empty)
        try fixture.habit("Walk")
        #expect(try fixture.build(days: 0) == .empty)
    }

    @Test(arguments: HabitPreset.allCases)
    func everyPresetMakesAUsableHabit(preset: HabitPreset) {
        let habit = preset.makeHabit(sortOrder: 0)
        #expect(!habit.name.isEmpty)
        #expect(habit.isAutomatic)
        #expect(habit.rule == preset.rule)
        #expect(habit.rule.target > 0)
        #expect(!preset.goalLabel.isEmpty)
        #expect(HabitPalette.hexes.contains(habit.colorHex))
    }
}
