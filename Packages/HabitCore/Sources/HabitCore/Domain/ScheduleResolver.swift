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
/// from before it existed — and nothing inside a pause is either.
public struct ScheduleResolver: Sendable {
    public let schedule: HabitSchedule
    public let calendar: DayCalendar
    /// The habit's creation day. `everyXDays` also counts its interval from here.
    public let anchor: DayKey
    /// Holidays, illness, the global off switch — already merged for this habit.
    public let pauses: [PauseSpan]

    public init(schedule: HabitSchedule, calendar: DayCalendar, anchor: DayKey, pauses: [PauseSpan] = []) {
        self.schedule = schedule.normalized
        self.calendar = calendar
        self.anchor = anchor
        self.pauses = pauses
    }

    public init(habit: Habit, calendar: DayCalendar, pauses: [PauseSpan] = []) {
        self.init(schedule: habit.schedule, calendar: calendar,
                  anchor: calendar.dayKey(for: habit.createdAt), pauses: pauses)
    }

    public func obligation(on key: DayKey) -> DayObligation {
        guard key >= anchor else { return .off }
        guard !pauses.covers(key) else { return .paused }
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

    /// The obligation `key` belongs to, or `nil` when nothing is owed — the day is off, or the
    /// whole period is behind the anchor or inside a pause.
    public func obligation(containing key: DayKey) -> ScheduleObligation? {
        switch schedule.period {
        case .day:
            guard obligation(on: key) == .required else { return nil }
            return ScheduleObligation(start: key, end: key, quota: 1, period: .day)
        case .week, .month:
            let bounds = periodBounds(containing: key)
            return obligation(for: bounds)
        }
    }

    /// Every obligation overlapping `from...to`, ascending. The last one may reach past `to`
    /// when a week or month is still running; callers decide whether to judge it. Periods that
    /// a pause swallowed whole are skipped rather than ending the walk.
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
            while cursor <= to {
                let bounds = periodBounds(containing: cursor)
                if let current = obligation(for: bounds) { result.append(current) }
                let next = calendar.key(byAdding: 1, to: bounds.end)
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

    private func periodBounds(containing key: DayKey) -> (start: DayKey, end: DayKey) {
        switch schedule.period {
        case .day:
            return (key, key)
        case .week:
            let start = calendar.startOfWeek(for: key)
            return (start, calendar.key(byAdding: 6, to: start))
        case .month:
            return (calendar.startOfMonth(for: key), calendar.endOfMonth(for: key))
        }
    }

    /// Scales the quota down to the days actually available — the habit may have been created
    /// part-way into the period, or part of it may be paused. A period with nothing available
    /// owes nothing at all.
    private func obligation(for bounds: (start: DayKey, end: DayKey)) -> ScheduleObligation? {
        let full = calendar.days(from: bounds.start, to: bounds.end) + 1
        guard full > 0 else { return nil }
        let days = calendar.keys(from: bounds.start, to: bounds.end)
        let available = days.count { $0 >= anchor && !pauses.covers($0) }
        guard available > 0 else { return nil }
        let effectiveStart = days.first { $0 >= anchor && !pauses.covers($0) } ?? bounds.start
        guard available < full else {
            return ScheduleObligation(start: bounds.start, end: bounds.end,
                                      quota: schedule.quota, period: schedule.period)
        }
        let scaled = Int((Double(schedule.quota) * Double(available) / Double(full)).rounded())
        return ScheduleObligation(start: effectiveStart, end: bounds.end,
                                  quota: min(max(scaled, 1), schedule.quota), period: schedule.period)
    }
}
