import Foundation

/// A calendar month laid out as weeks, each day carrying one stripe per habit.
///
/// The activity grid answers "how much happened", which is the wrong question once there are a
/// few habits: it cannot say *which* one lapsed. A month of stripes can, while still fitting on
/// a screen — and unlike a rolling window it lines up with how people picture a month.
public struct MonthGrid: Sendable, Equatable {
    /// One habit's colour and name, in the order the stripes are drawn.
    public struct Lane: Sendable, Equatable, Identifiable {
        public var id: UUID
        public var name: String
        public var emoji: String
        public var colorHex: String
        /// Kept days in the month, and what the month asked for.
        public var done: Int
        public var required: Int
    }

    public struct Day: Sendable, Equatable, Identifiable {
        public var key: DayKey
        public var dayOfMonth: Int
        /// One entry per lane, in the same order.
        public var states: [MatrixState]
        public var isToday: Bool
        /// Padding before the first and after the last of the month.
        public var isOutsideMonth: Bool

        public var id: String { key.raw }
    }

    public var month: DayKey
    public var lanes: [Lane]
    /// Always a whole number of weeks, starting on the calendar's first weekday.
    public var days: [Day]
    /// Weekday letters for the header, already rotated to the first weekday.
    public var weekdaySymbols: [String]

    public static let empty = MonthGrid(month: DayKey(raw: ""), lanes: [], days: [], weekdaySymbols: [])

    public var weeks: Int { days.count / 7 }

    /// More stripes than this stop being legible in a day cell, so the view falls back to a
    /// single intensity bar instead of drawing hairlines.
    public static let maxLegibleLanes = 5

    public static func build(habits: [Habit], logs: [DailyLog], calendar: DayCalendar,
                             today: DayKey, month: DayKey, pauses: [HabitPause] = []) -> MonthGrid {
        guard !habits.isEmpty else { return .empty }
        let first = calendar.startOfMonth(for: month)
        let last = calendar.endOfMonth(for: month)
        // Pad out to whole weeks so the grid is rectangular and the columns line up with the header.
        let gridStart = calendar.startOfWeek(for: first)
        let tail = calendar.startOfWeek(for: last)
        let gridEnd = calendar.key(byAdding: 6, to: tail)

        let logByHabitDay = logs.reduce(into: [UUID: [String: DailyLog]]()) { map, log in
            map[log.habitID, default: [:]][log.dayKey] = log
        }
        let resolvers = habits.map { ScheduleResolver(habit: $0, calendar: calendar, pauses: pauses.spans(for: $0.id)) }

        let keys = calendar.keys(from: gridStart, to: gridEnd)
        let days = keys.map { key -> Day in
            let outside = key < first || key > last
            let states = zip(habits, resolvers).map { habit, resolver -> MatrixState in
                if outside || key > today { return .upcoming }
                if logByHabitDay[habit.id]?[key.raw]?.isCompleted == true { return .done }
                switch resolver.obligation(on: key) {
                case .off, .flexible, .paused: return .off
                case .required:
                    let ratio = logByHabitDay[habit.id]?[key.raw]?.ratio ?? 0
                    return ratio > 0 ? .partial(ratio) : .missed
                }
            }
            return Day(key: key, dayOfMonth: key.components?.day ?? 0, states: states,
                       isToday: key == today, isOutsideMonth: outside)
        }

        let judgedEnd = min(last, today)
        let lanes = zip(habits, resolvers).map { habit, resolver -> Lane in
            let done = keys.count { key in
                key >= first && key <= last && logByHabitDay[habit.id]?[key.raw]?.isCompleted == true
            }
            let required = first <= judgedEnd ? resolver.demand(from: first, to: judgedEnd) : 0
            return Lane(id: habit.id, name: habit.name, emoji: habit.emoji,
                        colorHex: habit.colorHex, done: done, required: required)
        }

        return MonthGrid(month: first, lanes: lanes, days: days,
                         weekdaySymbols: symbols(calendar: calendar))
    }

    /// `veryShortStandaloneWeekdaySymbols` always starts at Sunday; rotate it to wherever the
    /// user's calendar starts, which is Monday almost everywhere outside the US.
    private static func symbols(calendar: DayCalendar) -> [String] {
        let all = calendar.calendar.veryShortStandaloneWeekdaySymbols
        guard all.count == 7 else { return all }
        let shift = calendar.calendar.firstWeekday - 1
        return (0..<7).map { all[($0 + shift) % 7] }
    }
}
