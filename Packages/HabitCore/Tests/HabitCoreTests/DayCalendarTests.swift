import Foundation
import Testing
@testable import HabitCore

@Suite("DayCalendar")
struct DayCalendarTests {
    let cal = DayCalendar(dayStartHour: 4, calendar: Fixed.calendar)

    @Test func lateNightBelongsToPreviousDay() {
        #expect(cal.dayKey(for: Fixed.date(2026, 9, 12, 3, 59)) == DayKey(raw: "2026-09-11"))
        #expect(cal.dayKey(for: Fixed.date(2026, 9, 12, 4, 0)) == DayKey(raw: "2026-09-12"))
        #expect(cal.dayKey(for: Fixed.date(2026, 9, 12, 23, 30)) == DayKey(raw: "2026-09-12"))
    }

    @Test func windowStartsAtDayStartHour() {
        let window = cal.window(for: DayKey(raw: "2026-09-12"))
        #expect(window.start == Fixed.date(2026, 9, 12, 4))
        #expect(window.end == Fixed.date(2026, 9, 13, 4))
        #expect(window.duration == 24 * 3600)
    }

    @Test func dstDayWindowIsTwentyThreeHours() {
        // US DST starts 2026-03-08 at 02:00 in New York.
        let window = cal.window(for: DayKey(raw: "2026-03-07"))
        #expect(window.duration == 23 * 3600)
        #expect(cal.dayKey(for: window.end.addingTimeInterval(-1)) == DayKey(raw: "2026-03-07"))
    }

    @Test func sleepWindowSpansTheNight() {
        let window = cal.sleepWindow(for: DayKey(raw: "2026-09-12"))
        #expect(window.start == Fixed.date(2026, 9, 11, 18))
        #expect(window.end == Fixed.date(2026, 9, 12, 14))
    }

    @Test func keyArithmeticAndWeekday() {
        let key = DayKey(raw: "2026-09-12")  // Saturday
        #expect(cal.weekday(for: key) == 7)
        #expect(cal.key(byAdding: 1, to: key) == DayKey(raw: "2026-09-13"))
        #expect(cal.key(byAdding: -12, to: key) == DayKey(raw: "2026-08-31"))
        #expect(cal.keys(from: DayKey(raw: "2026-09-10"), to: key).count == 3)
        #expect(cal.keys(from: key, to: DayKey(raw: "2026-09-10")).isEmpty)
    }

    @Test func dayStartHourIsClamped() {
        #expect(DayCalendar(dayStartHour: 9).dayStartHour == 6)
        #expect(DayCalendar(dayStartHour: -2).dayStartHour == 0)
    }

    @Test func dayKeyOrdering() {
        #expect(DayKey(raw: "2026-01-31") < DayKey(raw: "2026-02-01"))
        #expect(DayKey(year: 2026, month: 2, day: 1).raw == "2026-02-01")
    }
}
