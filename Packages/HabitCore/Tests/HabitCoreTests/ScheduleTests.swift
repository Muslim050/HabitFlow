import Foundation
import Testing
@testable import HabitCore

/// Weeks start where the user's calendar says they do, so every test that touches a week
/// boundary states which convention it is using.
private func calendar(firstWeekday: Int) -> DayCalendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = Fixed.timeZone
    c.locale = Locale(identifier: "en_US_POSIX")
    c.firstWeekday = firstWeekday
    return DayCalendar(dayStartHour: 4, calendar: c)
}

private let monday = calendar(firstWeekday: 2)
private let sunday = calendar(firstWeekday: 1)

/// 2026-09-19 is a Saturday.
private let saturday = DayKey(raw: "2026-09-19")

@Suite("HabitSchedule")
struct HabitScheduleTests {
    @Test func normalizationCollapsesDegenerateCases() {
        #expect(HabitSchedule.weekdays(mask: HabitSchedule.everyDayMask).normalized == .everyDay)
        #expect(HabitSchedule.everyXDays(interval: 1).normalized == .everyDay)
        #expect(HabitSchedule.timesPerWeek(count: 99).normalized == .timesPerWeek(count: 7))
        #expect(HabitSchedule.timesPerWeek(count: 0).normalized == .timesPerWeek(count: 1))
    }

    @Test func periodAndQuota() {
        #expect(HabitSchedule.everyDay.period == .day)
        #expect(HabitSchedule.everyDay.quota == 1)
        #expect(HabitSchedule.timesPerWeek(count: 3).period == .week)
        #expect(HabitSchedule.timesPerWeek(count: 3).quota == 3)
        #expect(HabitSchedule.timesPerMonth(count: 8).period == .month)
        #expect(!HabitSchedule.everyXDays(interval: 3).isFlexible)
    }

    @Test func codingRoundTrips() throws {
        for schedule: HabitSchedule in [.everyDay, .weekdays(mask: 0b011_1110),
                                        .timesPerWeek(count: 3), .timesPerMonth(count: 10),
                                        .everyXDays(interval: 3)] {
            let data = try HabitScheduleCoding.encode(schedule)
            #expect(HabitScheduleCoding.decode(data) == schedule)
        }
        #expect(HabitScheduleCoding.decode(Data()) == nil, "empty data means a pre-V2 row, not a default")
    }
}

@Suite("ScheduleResolver")
struct ScheduleResolverTests {
    private func resolver(_ schedule: HabitSchedule, _ cal: DayCalendar = monday,
                          anchor: DayKey = DayKey(raw: "2026-01-01")) -> ScheduleResolver {
        ScheduleResolver(schedule: schedule, calendar: cal, anchor: anchor)
    }

    // MARK: Which days are named

    @Test func nothingIsDueBeforeTheHabitExisted() {
        let r = resolver(.everyDay, anchor: DayKey(raw: "2026-09-15"))
        #expect(r.obligation(on: DayKey(raw: "2026-09-14")) == .off)
        #expect(r.obligation(on: DayKey(raw: "2026-09-15")) == .required)
    }

    @Test func weekdaysNameOnlyTheirDays() {
        let r = resolver(.weekdays(mask: 0b000_0010))   // Monday only
        #expect(r.obligation(on: DayKey(raw: "2026-09-14")) == .required)  // Monday
        #expect(r.obligation(on: DayKey(raw: "2026-09-15")) == .off)       // Tuesday
    }

    @Test func everyXDaysCountsFromTheAnchor() {
        let r = resolver(.everyXDays(interval: 3), anchor: DayKey(raw: "2026-09-14"))
        #expect(r.obligation(on: DayKey(raw: "2026-09-14")) == .required)
        #expect(r.obligation(on: DayKey(raw: "2026-09-15")) == .off)
        #expect(r.obligation(on: DayKey(raw: "2026-09-17")) == .required)
        #expect(r.obligation(on: DayKey(raw: "2026-09-20")) == .required)
    }

    @Test func aQuotaLeavesEveryDayOpen() {
        let r = resolver(.timesPerWeek(count: 3))
        for day in 14...20 {
            #expect(r.obligation(on: DayKey(raw: "2026-09-\(day)")) == .flexible)
        }
    }

    // MARK: Period boundaries

    @Test func theWeekStartsWhereTheCalendarSaysItDoes() {
        let fromMonday = resolver(.timesPerWeek(count: 3), monday).obligation(containing: saturday)
        #expect(fromMonday?.start == DayKey(raw: "2026-09-14"))
        #expect(fromMonday?.end == DayKey(raw: "2026-09-20"))

        let fromSunday = resolver(.timesPerWeek(count: 3), sunday).obligation(containing: saturday)
        #expect(fromSunday?.start == DayKey(raw: "2026-09-13"))
        #expect(fromSunday?.end == DayKey(raw: "2026-09-19"))
    }

    @Test func theMonthSpansTheCalendarMonth() {
        let september = resolver(.timesPerMonth(count: 8)).obligation(containing: saturday)
        #expect(september?.start == DayKey(raw: "2026-09-01"))
        #expect(september?.end == DayKey(raw: "2026-09-30"))

        let february = resolver(.timesPerMonth(count: 8)).obligation(containing: DayKey(raw: "2026-02-10"))
        #expect(february?.end == DayKey(raw: "2026-02-28"), "2026 is not a leap year")
    }

    @Test func aHabitCreatedMidWeekOwesLess() {
        // Created Thursday: three days of a seven-day week remain, so three-a-week asks for one.
        let r = resolver(.timesPerWeek(count: 3), monday, anchor: DayKey(raw: "2026-09-18"))
        let week = r.obligation(containing: saturday)
        #expect(week?.start == DayKey(raw: "2026-09-18"), "clipped to the day the habit appeared")
        #expect(week?.quota == 1)
    }

    @Test func obligationsCoverTheRangeWithoutOverlapping() {
        let r = resolver(.timesPerWeek(count: 2), monday, anchor: DayKey(raw: "2026-09-01"))
        let weeks = r.obligations(from: DayKey(raw: "2026-09-07"), to: DayKey(raw: "2026-09-27"))
        #expect(weeks.count == 3)
        #expect(weeks.map(\.start.raw) == ["2026-09-07", "2026-09-14", "2026-09-21"])
    }

    // MARK: Demand

    @Test func demandProratesAPartlyCoveredPeriod() {
        let r = resolver(.timesPerWeek(count: 3), monday, anchor: DayKey(raw: "2026-01-01"))
        // One aligned week asks for exactly the quota.
        #expect(r.demand(from: DayKey(raw: "2026-09-14"), to: DayKey(raw: "2026-09-20")) == 3)
        // A seven-day window straddling two weeks still adds up to about a week's worth.
        #expect(r.demand(from: DayKey(raw: "2026-09-17"), to: DayKey(raw: "2026-09-23")) == 3)
    }

    @Test func demandOnNamedDaysCountsThem() {
        let r = resolver(.weekdays(mask: 0b011_1110), monday, anchor: DayKey(raw: "2026-01-01"))
        #expect(r.demand(from: DayKey(raw: "2026-09-14"), to: DayKey(raw: "2026-09-20")) == 5)
    }
}
