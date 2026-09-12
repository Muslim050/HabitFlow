import Foundation
import SwiftData
import Testing
@testable import HabitCore

@Suite("AgendaDraft")
struct AgendaDraftTests {
    @Test func validityNeedsATitle() {
        var draft = AgendaDraft()
        #expect(!draft.isValid)
        draft.title = "   "
        #expect(!draft.isValid)
        draft.title = "  Gym  "
        #expect(draft.isValid)
        #expect(draft.trimmedTitle == "Gym")
    }

    @Test func endFollowsDuration() {
        let start = Fixed.date(2026, 9, 12, 18)
        let draft = AgendaDraft(title: "Gym", date: start, durationMinutes: 45)
        #expect(draft.endDate == start.addingTimeInterval(45 * 60))
    }

    @Test func weekdaysPerRepeatRule() {
        let saturday = Fixed.date(2026, 9, 12, 18)
        func rule(_ value: AgendaDraft.Repeat) -> [Int]? {
            AgendaDraft(title: "x", date: saturday, repeats: value).weekdays(calendar: Fixed.calendar)
        }
        #expect(rule(.never) == nil)
        #expect(rule(.daily) == nil)
        #expect(rule(.weekdays) == [2, 3, 4, 5, 6])
        #expect(rule(.weekly) == [7], "the draft's own day")
    }

    @Test func quarterHourRounding() {
        let calendar = Fixed.calendar
        func next(_ h: Int, _ m: Int) -> (Int, Int) {
            let date = AgendaDraft.nextQuarterHour(after: Fixed.date(2026, 9, 12, h, m), calendar: calendar)
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            return (parts.hour ?? 0, parts.minute ?? 0)
        }
        #expect(next(14, 7) == (14, 15))
        #expect(next(14, 15) == (14, 30), "already on the mark moves to the next slot")
        #expect(next(14, 59) == (15, 0))
    }
}

@Suite("HabitSchedulingSuggestion")
@MainActor
struct HabitSchedulingSuggestionTests {
    @MainActor
    struct Fixture {
        let container: ModelContainer
        let repository: SwiftDataHabitRepository
        let calendar: DayCalendar
        let now = Fixed.date(2026, 9, 12, 10)

        init() throws {
            container = try ModelContainerFactory.inMemory()
            repository = SwiftDataHabitRepository(container: container)
            calendar = DayCalendar(dayStartHour: 4, calendar: Fixed.calendar)
        }

        func habit(_ name: String, rule: HabitRule = .manual, mask: Int = Habit.everyDayMask) throws -> Habit {
            let habit = Habit(name: name, rule: rule, scheduleMask: mask,
                              createdAt: now.addingTimeInterval(-40 * 86_400))
            repository.insert(habit)
            try repository.save()
            return habit
        }

        func completions(_ habit: Habit, hours: [Int]) throws -> [DailyLog] {
            var logs: [DailyLog] = []
            for (offset, hour) in hours.enumerated() {
                let key = calendar.key(byAdding: -(offset + 1), to: calendar.dayKey(for: now))
                let log = try repository.fetchOrCreateLog(habitID: habit.id, dayKey: key,
                                                          dayStart: calendar.dayStart(for: key), target: 1)
                log.isCompleted = true
                var parts = Fixed.calendar.dateComponents([.year, .month, .day], from: calendar.dayStart(for: key))
                parts.hour = hour
                log.completedAt = Fixed.calendar.date(from: parts)
                logs.append(log)
            }
            try repository.save()
            return logs
        }
    }

    @Test func usesTheHourYouActuallyCloseIt() throws {
        let fixture = try Fixture()
        let habit = try fixture.habit("Gym")
        let logs = try fixture.completions(habit, hours: [19, 19, 20, 19, 18])

        let result = HabitSchedulingSuggestion.suggest(habit: habit, logs: logs,
                                                       calendar: fixture.calendar, now: fixture.now)
        #expect(result.fromHistory)
        #expect(result.sampleCount == 5)
        let hour = Fixed.calendar.component(.hour, from: result.draft.date)
        #expect(hour == 19, "the median of the real completions")
        #expect(result.draft.title == "Gym")
    }

    @Test func fallsBackWhenHistoryIsThin() throws {
        let fixture = try Fixture()
        let habit = try fixture.habit("Read")
        let logs = try fixture.completions(habit, hours: [7, 8])

        let result = HabitSchedulingSuggestion.suggest(habit: habit, logs: logs,
                                                       calendar: fixture.calendar, now: fixture.now,
                                                       fallbackHour: 21)
        #expect(!result.fromHistory)
        #expect(Fixed.calendar.component(.hour, from: result.draft.date) == 21)
    }

    @Test func neverSuggestsAMomentThatHasPassed() throws {
        let fixture = try Fixture()
        let habit = try fixture.habit("Morning walk")
        let logs = try fixture.completions(habit, hours: [7, 7, 7, 7])

        let result = HabitSchedulingSuggestion.suggest(habit: habit, logs: logs,
                                                       calendar: fixture.calendar, now: fixture.now)
        #expect(result.draft.date > fixture.now, "07:00 already went by, so it lands tomorrow")
    }

    @Test func durationComesFromTheRuleWhereTheRuleKnows() throws {
        let fixture = try Fixture()
        let gym = try fixture.habit("Gym", rule: .geofence(latitude: 0, longitude: 0, radius: 150,
                                                           minDwellMinutes: 45, placeName: "Gym"))
        let workout = try fixture.habit("Run", rule: .healthWorkout(activityRaw: nil, minMinutes: 30))
        let manual = try fixture.habit("Read")

        #expect(HabitSchedulingSuggestion.suggestedDuration(for: gym) == 45)
        #expect(HabitSchedulingSuggestion.suggestedDuration(for: workout) == 30)
        #expect(HabitSchedulingSuggestion.suggestedDuration(for: manual) == 60)
    }

    @Test func repeatFollowsTheHabitSchedule() throws {
        let fixture = try Fixture()
        let everyDay = try fixture.habit("Walk")
        let someDays = try fixture.habit("Gym", mask: 0b010_1010)

        #expect(HabitSchedulingSuggestion.suggest(habit: everyDay, logs: [], calendar: fixture.calendar,
                                                  now: fixture.now).draft.repeats == .daily)
        #expect(HabitSchedulingSuggestion.suggest(habit: someDays, logs: [], calendar: fixture.calendar,
                                                  now: fixture.now).draft.repeats == .weekly)
    }
}
