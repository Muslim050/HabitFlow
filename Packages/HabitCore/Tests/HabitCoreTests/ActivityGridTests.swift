import Foundation
import SwiftData
import Testing
@testable import HabitCore

@Suite("ActivityGrid")
@MainActor
struct ActivityGridTests {
    /// Fixed clock and calendar so the grid never depends on the machine's date.
    @MainActor
    struct Fixture {
        let container: ModelContainer
        let repository: SwiftDataHabitRepository
        let calendar: DayCalendar
        let today: DayKey
        let now: Date

        init(now: Date = Fixed.date(2026, 9, 12, 10)) throws {
            container = try ModelContainerFactory.inMemory()
            repository = SwiftDataHabitRepository(container: container)
            calendar = DayCalendar(dayStartHour: 4, calendar: Fixed.calendar)
            self.now = now
            today = calendar.dayKey(for: now)
        }

        @discardableResult
        func habit(_ name: String, createdDaysAgo: Int = 60, schedule: HabitSchedule = .everyDay) throws -> Habit {
            let created = calendar.dayStart(for: calendar.key(byAdding: -createdDaysAgo, to: today))
            let habit = Habit(name: name, rule: .manual, schedule: schedule, createdAt: created)
            repository.insert(habit)
            try repository.save()
            return habit
        }

        /// Marks the habit completed on each of the given offsets back from today.
        func complete(_ habit: Habit, daysAgo: [Int]) throws {
            for offset in daysAgo {
                let key = calendar.key(byAdding: -offset, to: today)
                let log = try repository.fetchOrCreateLog(habitID: habit.id, dayKey: key,
                                                          dayStart: calendar.dayStart(for: key), target: 1)
                log.isCompleted = true
                log.progressValue = 1
                log.completedAt = calendar.dayStart(for: key).addingTimeInterval(9 * 3600)
            }
            try repository.save()
        }

        func build(weeks: Int = 16) throws -> ActivitySummary {
            ActivityGrid.build(habits: try repository.activeHabits(),
                               logs: try repository.logs(from: calendar.key(byAdding: -400, to: today), to: today),
                               calendar: calendar, today: today, weeks: weeks)
        }
    }

    @Test func gridEndsOnTodayAndKeepsWeekdayRowsAligned() throws {
        let fixture = try Fixture()
        try fixture.habit("Read")
        let summary = try fixture.build(weeks: 16)

        #expect(summary.days.count == 16 * 7)
        let real = summary.days.compactMap { $0 }
        #expect(real.last?.dayKey == fixture.today)
        // 2026-09-12 is a Saturday (weekday 7), so the last column is full.
        #expect(summary.days.suffix(1).allSatisfy { $0 != nil })
        // Every row index maps to one weekday.
        for (index, day) in summary.days.enumerated() {
            guard let day else { continue }
            #expect(fixture.calendar.weekday(for: day.dayKey) == index % 7 + 1)
        }
    }

    @Test func daysBeforeAHabitExistedAreNotMisses() throws {
        let fixture = try Fixture()
        try fixture.habit("Read", createdDaysAgo: 3)
        let summary = try fixture.build()
        let real = summary.days.compactMap { $0 }

        let old = try #require(real.first)
        #expect(old.scheduled == 0, "a habit created three days ago was never due last month")
        #expect(old.isOffDay)
        let recent = try #require(real.first { $0.dayKey == fixture.calendar.key(byAdding: -1, to: fixture.today) })
        #expect(recent.scheduled == 1)
    }

    @Test func unscheduledWeekdaysAreOffDaysNotMisses() throws {
        let fixture = try Fixture()
        // Weekdays only: bit 0 is Sunday, bit 6 is Saturday.
        try fixture.habit("Gym", schedule: .weekdays(mask: 0b011_1110))
        let summary = try fixture.build()
        // Take the most recent of each weekday: the earliest columns predate the habit and are
        // off days for a different reason.
        let real = summary.days.compactMap { $0 }
        let saturday = try #require(real.last { fixture.calendar.weekday(for: $0.dayKey) == 7 })
        #expect(saturday.isOffDay)
        let wednesday = try #require(real.last { fixture.calendar.weekday(for: $0.dayKey) == 4 })
        #expect(wednesday.scheduled == 1)
    }

    @Test func levelsSplitPartialDays() throws {
        let fixture = try Fixture()
        let a = try fixture.habit("A")
        let b = try fixture.habit("B")
        let c = try fixture.habit("C")
        try fixture.complete(a, daysAgo: [1])            // 1 of 3
        try fixture.complete(a, daysAgo: [2])
        try fixture.complete(b, daysAgo: [2])            // 2 of 3
        try fixture.complete(a, daysAgo: [3])
        try fixture.complete(b, daysAgo: [3])
        try fixture.complete(c, daysAgo: [3])            // 3 of 3

        let real = try fixture.build().days.compactMap { $0 }
        func day(_ ago: Int) throws -> ActivityDay {
            try #require(real.first { $0.dayKey == fixture.calendar.key(byAdding: -ago, to: fixture.today) })
        }
        let one = try day(1), two = try day(2), three = try day(3), four = try day(4)
        #expect(one.level == 1)
        #expect(two.level == 2)
        #expect(three.level == 4)
        #expect(four.level == 0)
        #expect(three.isPerfect)
        #expect(!two.isPerfect)
    }

    @Test func countsAndStreaks() throws {
        let fixture = try Fixture()
        let a = try fixture.habit("A")
        let b = try fixture.habit("B")
        // Active on the last four days; day 5 empty; active on 6 and 7.
        try fixture.complete(a, daysAgo: [0, 1, 2, 3, 6, 7])
        try fixture.complete(b, daysAgo: [1, 3])

        let summary = try fixture.build()
        #expect(summary.activeDays == 6)
        #expect(summary.perfectDays == 2, "only the days where both habits closed")
        #expect(summary.totalCompletions == 8)
        #expect(summary.currentStreak == 4)
        #expect(summary.bestStreak == 4)
    }

    @Test func todayInProgressDoesNotBreakTheStreak() throws {
        let fixture = try Fixture()
        let a = try fixture.habit("A")
        try fixture.complete(a, daysAgo: [1, 2, 3])   // nothing closed today yet

        let summary = try fixture.build()
        #expect(summary.currentStreak == 3)
    }

    @Test func offDaysDoNotBreakTheStreak() throws {
        let fixture = try Fixture()
        let gym = try fixture.habit("Gym", schedule: .weekdays(mask: 0b011_1110))  // weekdays only
        // 2026-09-12 is Saturday: yesterday Friday, and 09-06 is a Sunday inside the run.
        try fixture.complete(gym, daysAgo: [1, 2, 3, 4, 5, 8, 9])
        let summary = try fixture.build()
        #expect(summary.currentStreak >= 7, "the weekend in the middle is skipped, not counted as a miss")
    }

    @Test func aTickOnAnUnscheduledDayStillCountsAsActivity() throws {
        let fixture = try Fixture()
        // Weekdays only, but the person marked it done on a Saturday.
        let gym = try fixture.habit("Gym", schedule: .weekdays(mask: 0b011_1110))
        try fixture.complete(gym, daysAgo: [0])   // 2026-09-12 is a Saturday

        let summary = try fixture.build()
        let today = try #require(summary.days.compactMap { $0 }.last)
        #expect(today.scheduled == 0)
        #expect(today.completed == 1)
        #expect(!today.isOffDay, "a day with a completion is never an off day")
        #expect(today.level == 4)
        #expect(!today.isPerfect, "nothing was due, so there was nothing to be perfect about")
        #expect(summary.activeDays == 1)
        #expect(summary.currentStreak == 1)
    }

    @Test func emptyStateIsSafe() throws {
        let fixture = try Fixture()
        let summary = try fixture.build()
        #expect(summary.activeDays == 0)
        #expect(summary.currentStreak == 0)
        #expect(summary.bestStreak == 0)
        #expect(summary.days.compactMap { $0 }.allSatisfy { $0.isOffDay })
        #expect(ActivityGrid.build(habits: [], logs: [], calendar: fixture.calendar, today: fixture.today, weeks: 0) == .empty)
    }

    @Test func monthLabelsAreSpacedOut() throws {
        let fixture = try Fixture()
        try fixture.habit("Read")
        let summary = try fixture.build(weeks: 26)
        let labels = ActivityGrid.monthLabels(days: summary.days, calendar: fixture.calendar,
                                              locale: Locale(identifier: "en_US"))
        #expect(!labels.isEmpty)
        let columns = labels.keys.sorted()
        for (a, b) in zip(columns, columns.dropFirst()) {
            #expect(b - a >= 3, "labels never crowd each other")
        }
        #expect(columns.allSatisfy { $0 >= 0 && $0 < 26 })
    }
}
