import Foundation

/// One thing the schedule asks for: a named day, or a period that wants `quota` completions.
public struct ScheduleObligation: Sendable, Equatable {
    public var start: DayKey
    /// Inclusive.
    public var end: DayKey
    public var quota: Int
    public var period: SchedulePeriod

    public init(start: DayKey, end: DayKey, quota: Int, period: SchedulePeriod) {
        self.start = start
        self.end = end
        self.quota = quota
        self.period = period
    }

    public func contains(_ key: DayKey) -> Bool { key >= start && key <= end }
}

/// Turns a schedule into answers about concrete days: is this day due, and which obligation
/// does it belong to. Nothing before `anchor` is ever due — a habit cannot have missed days
/// from before it existed.
public struct ScheduleResolver: Sendable {
    public let schedule: HabitSchedule
    public let calendar: DayCalendar
    /// The habit's creation day. `everyXDays` also counts its interval from here.
    public let anchor: DayKey

    public init(schedule: HabitSchedule, calendar: DayCalendar, anchor: DayKey) {
        self.schedule = schedule.normalized
        self.calendar = calendar
        self.anchor = anchor
    }

    public init(habit: Habit, calendar: DayCalendar) {
        self.init(schedule: habit.schedule, calendar: calendar,
                  anchor: calendar.dayKey(for: habit.createdAt))
    }

    public func obligation(on key: DayKey) -> DayObligation {
        guard key >= anchor else { return .off }
        switch schedule {
        case .everyDay:
            return .required
        case .weekdays(let mask):
            let weekday = calendar.weekday(for: key)
            guard (1...7).contains(weekday) else { return .off }
            return mask & (1 << (weekday - 1)) != 0 ? .required : .off
        case .everyXDays(let interval):
            return calendar.days(from: anchor, to: key) % interval == 0 ? .required : .off
        case .timesPerWeek, .timesPerMonth:
            return .flexible
        }
    }

    /// The obligation `key` belongs to, or `nil` when the day is not due at all.
    /// A period is clipped to `anchor`: a habit created mid-week owes only the rest of that week.
    public func obligation(containing key: DayKey) -> ScheduleObligation? {
        guard obligation(on: key) != .off else { return nil }
        switch schedule.period {
        case .day:
            return ScheduleObligation(start: key, end: key, quota: 1, period: .day)
        case .week:
            let start = calendar.startOfWeek(for: key)
            let end = calendar.key(byAdding: 6, to: start)
            return clipped(start: start, end: end, period: .week)
        case .month:
            return clipped(start: calendar.startOfMonth(for: key),
                           end: calendar.endOfMonth(for: key), period: .month)
        }
    }

    /// Every obligation overlapping `from...to`, ascending. The last one may reach past `to`
    /// when a week or month is still running; callers decide whether to judge it.
    public func obligations(from: DayKey, to: DayKey) -> [ScheduleObligation] {
        let first = max(from, anchor)
        guard first <= to else { return [] }
        switch schedule.period {
        case .day:
            return calendar.keys(from: first, to: to)
                .filter { obligation(on: $0) == .required }
                .map { ScheduleObligation(start: $0, end: $0, quota: 1, period: .day) }
        case .week, .month:
            var result: [ScheduleObligation] = []
            var cursor = first
            while cursor <= to, let current = obligation(containing: cursor) {
                result.append(current)
                let next = calendar.key(byAdding: 1, to: current.end)
                if next <= cursor { break }
                cursor = next
            }
            return result
        }
    }

    /// How much the schedule asks for inside `from...to`. A period that only partly overlaps the
    /// range is prorated, so a seven-day window over a "three times a week" habit asks for three
    /// whether or not the window is aligned to the week.
    public func demand(from: DayKey, to: DayKey) -> Int {
        let first = max(from, anchor)
        guard first <= to else { return 0 }
        switch schedule.period {
        case .day:
            return calendar.keys(from: first, to: to).count { obligation(on: $0) == .required }
        case .week, .month:
            return obligations(from: first, to: to).reduce(0) { total, obligation in
                let span = calendar.days(from: obligation.start, to: obligation.end) + 1
                let inside = calendar.days(from: max(obligation.start, first), to: min(obligation.end, to)) + 1
                guard span > 0, inside > 0 else { return total }
                return total + Int((Double(obligation.quota) * Double(inside) / Double(span)).rounded())
            }
        }
    }

    /// Scales the quota down when the habit was created part-way into the period, so its first
    /// week does not count as a miss for days it did not exist.
    private func clipped(start: DayKey, end: DayKey, period: SchedulePeriod) -> ScheduleObligation {
        let full = calendar.days(from: start, to: end) + 1
        let effectiveStart = max(start, anchor)
        let available = calendar.days(from: effectiveStart, to: end) + 1
        guard full > 0, available > 0, available < full else {
            return ScheduleObligation(start: effectiveStart, end: end, quota: schedule.quota, period: period)
        }
        let scaled = Int((Double(schedule.quota) * Double(available) / Double(full)).rounded())
        return ScheduleObligation(start: effectiveStart, end: end,
                                  quota: min(max(scaled, 1), schedule.quota), period: period)
    }
}
