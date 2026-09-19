import Foundation

/// Logical-day arithmetic. A day starts at `dayStartHour` (default 04:00) so a late night
/// still belongs to "yesterday". All windows are computed with `Calendar` so DST is respected.
public struct DayCalendar: Sendable {
    public var dayStartHour: Int
    public var calendar: Calendar

    public static let sleepWindowHalfSpan: TimeInterval = 10 * 3600

    public init(dayStartHour: Int = 4, calendar: Calendar = .current) {
        self.dayStartHour = min(max(dayStartHour, 0), 6)
        self.calendar = calendar
    }

    public func dayKey(for date: Date) -> DayKey {
        let shifted = calendar.date(byAdding: .hour, value: -dayStartHour, to: date) ?? date
        let c = calendar.dateComponents([.year, .month, .day], from: shifted)
        return DayKey(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    /// The instant the logical day begins.
    public func dayStart(for key: DayKey) -> Date {
        guard let (y, m, d) = key.components else { return Date.distantPast }
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d; comps.hour = dayStartHour
        return calendar.date(from: comps) ?? Date.distantPast
    }

    /// `[dayStart, nextDayStart)`.
    public func window(for key: DayKey) -> DateInterval {
        let start = dayStart(for: key)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return DateInterval(start: start, end: end)
    }

    /// Night window used for sleep: ±10 h around the day start (04:00 → 18:00 yesterday … 14:00 today).
    public func sleepWindow(for key: DayKey) -> DateInterval {
        let start = dayStart(for: key)
        return DateInterval(start: start.addingTimeInterval(-Self.sleepWindowHalfSpan),
                            end: start.addingTimeInterval(Self.sleepWindowHalfSpan))
    }

    public func key(byAdding days: Int, to key: DayKey) -> DayKey {
        let base = dayStart(for: key)
        let shifted = calendar.date(byAdding: .day, value: days, to: base) ?? base
        return dayKey(for: shifted)
    }

    /// 1 = Sunday … 7 = Saturday, matching `Calendar.component(.weekday)`.
    public func weekday(for key: DayKey) -> Int {
        calendar.component(.weekday, from: dayStart(for: key))
    }

    /// Inclusive range of keys, ascending.
    public func keys(from: DayKey, to: DayKey) -> [DayKey] {
        guard from <= to else { return [] }
        var result: [DayKey] = []
        var cursor = from
        while cursor <= to {
            result.append(cursor)
            let next = key(byAdding: 1, to: cursor)
            if next <= cursor { break }
            cursor = next
        }
        return result
    }

    /// Whole logical days between two keys; negative when `to` precedes `from`.
    public func days(from: DayKey, to: DayKey) -> Int {
        calendar.dateComponents([.day], from: dayStart(for: from), to: dayStart(for: to)).day ?? 0
    }

    /// First day of the week `key` falls in, honouring the calendar's `firstWeekday`
    /// (Monday in most of Europe, Sunday in the US).
    public func startOfWeek(for key: DayKey) -> DayKey {
        let offset = (weekday(for: key) - calendar.firstWeekday + 7) % 7
        return self.key(byAdding: -offset, to: key)
    }

    public func startOfMonth(for key: DayKey) -> DayKey {
        guard let (y, m, _) = key.components else { return key }
        return DayKey(year: y, month: m, day: 1)
    }

    public func endOfMonth(for key: DayKey) -> DayKey {
        guard let (y, m, _) = key.components,
              let length = calendar.range(of: .day, in: .month, for: dayStart(for: key))?.count
        else { return key }
        return DayKey(year: y, month: m, day: length)
    }

    public func today(now: Date = Date()) -> DayKey { dayKey(for: now) }
}
