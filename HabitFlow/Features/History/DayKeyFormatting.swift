import Foundation
import HabitCore

extension DayKey {
    /// A logical day written the way the reader's locale writes dates. The raw `yyyy-MM-dd`
    /// is a storage key, never something to put in front of a person.
    func formatted(_ style: Date.FormatStyle.DateStyle = .abbreviated, calendar: DayCalendar) -> String {
        guard let parts = components else { return raw }
        var comps = DateComponents()
        comps.year = parts.year; comps.month = parts.month; comps.day = parts.day
        comps.hour = 12  // noon keeps the date stable across DST shifts
        guard let date = calendar.calendar.date(from: comps) else { return raw }
        return date.formatted(.dateTime.day().month(style == .abbreviated ? .abbreviated : .wide).year())
    }
}
