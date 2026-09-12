import Foundation

/// One day across every habit, the unit of the contribution-style grid.
public struct ActivityDay: Sendable, Equatable, Identifiable {
    public var dayKey: DayKey
    /// Habits that were scheduled on this day AND already existed.
    public var scheduled: Int
    public var completed: Int

    public var id: String { dayKey.raw }
    /// Nothing was due and nothing was done — an off day, not a miss. A habit ticked on a
    /// day it was not scheduled still makes the day active, so this needs both to be zero.
    public var isOffDay: Bool { scheduled == 0 && completed == 0 }
    public var ratio: Double {
        let denominator = max(scheduled, completed)
        return denominator > 0 ? Double(completed) / Double(denominator) : 0
    }
    /// Everything that was due got closed. A bonus tick on an off day is active, not perfect.
    public var isPerfect: Bool { scheduled > 0 && completed >= scheduled }
    public var isActive: Bool { completed > 0 }

    public init(dayKey: DayKey, scheduled: Int, completed: Int) {
        self.dayKey = dayKey
        self.scheduled = scheduled
        self.completed = completed
    }

    /// Five buckets, matching what a contribution grid can distinguish at small cell sizes.
    public var level: Int {
        guard completed > 0 else { return 0 }
        // Closed on a day nothing was due: the day is as full as it could be.
        if scheduled == 0 || completed >= scheduled { return 4 }
        switch ratio {
        case ..<0.34: return 1
        case ..<0.67: return 2
        default: return 3
        }
    }
}

public struct ActivitySummary: Sendable, Equatable {
    /// Ascending, ending on `today`. `nil` entries pad the last column so weekday rows stay aligned.
    public var days: [ActivityDay?]
    /// Days where every scheduled habit closed.
    public var perfectDays: Int
    /// Days where at least one habit closed — the grid's equivalent of a contribution.
    public var activeDays: Int
    public var totalCompletions: Int
    /// Consecutive active days ending today; off days are skipped, today in progress does not break it.
    public var currentStreak: Int
    public var bestStreak: Int

    public static let empty = ActivitySummary(days: [], perfectDays: 0, activeDays: 0,
                                              totalCompletions: 0, currentStreak: 0, bestStreak: 0)
}

/// Builds the all-habits activity grid. Deliberately conservative about the past:
/// a habit created last week was never "due" the week before, so those days are not misses.
public enum ActivityGrid {

    public static func build(habits: [Habit], logs: [DailyLog], calendar: DayCalendar,
                             today: DayKey, weeks: Int) -> ActivitySummary {
        guard weeks > 0 else { return .empty }

        // The grid ends on today's column; pad the rest of that column so rows stay weekday-aligned.
        let trailingPad = 7 - calendar.weekday(for: today)
        let totalDays = weeks * 7 - trailingPad
        guard totalDays > 0 else { return .empty }
        let start = calendar.key(byAdding: -(totalDays - 1), to: today)

        let completedByDay = logs.reduce(into: [String: Int]()) { counts, log in
            if log.isCompleted { counts[log.dayKey, default: 0] += 1 }
        }
        let firstDayOf = habits.reduce(into: [UUID: DayKey]()) { map, habit in
            map[habit.id] = calendar.dayKey(for: habit.createdAt)
        }

        var days: [ActivityDay?] = calendar.keys(from: start, to: today).map { key in
            let weekday = calendar.weekday(for: key)
            let scheduled = habits.filter { habit in
                guard let first = firstDayOf[habit.id], first <= key else { return false }
                return habit.isScheduled(weekday: weekday)
            }.count
            return ActivityDay(dayKey: key, scheduled: scheduled, completed: completedByDay[key.raw] ?? 0)
        }
        let real = days.compactMap { $0 }
        days.append(contentsOf: Array(repeating: nil, count: trailingPad))

        return ActivitySummary(
            days: days,
            perfectDays: real.filter(\.isPerfect).count,
            activeDays: real.filter(\.isActive).count,
            totalCompletions: real.reduce(0) { $0 + $1.completed },
            currentStreak: currentStreak(real, today: today),
            bestStreak: bestStreak(real)
        )
    }

    /// Walks back from today. Today counts only when something closed, so an untouched
    /// morning never reads as a broken streak.
    static func currentStreak(_ days: [ActivityDay], today: DayKey) -> Int {
        var streak = 0
        for day in days.reversed() {
            if day.dayKey == today {
                if day.isActive { streak += 1 }
                continue
            }
            if day.isOffDay { continue }
            if day.isActive { streak += 1 } else { break }
        }
        return streak
    }

    static func bestStreak(_ days: [ActivityDay]) -> Int {
        var best = 0
        var run = 0
        for day in days {
            if day.isOffDay { continue }
            if day.isActive {
                run += 1
                best = max(best, run)
            } else {
                run = 0
            }
        }
        return best
    }

    /// Column index -> month name, for the strip above the grid. Only the first column of a
    /// month is labelled, and only when the month has room to show it.
    public static func monthLabels(days: [ActivityDay?], calendar: DayCalendar,
                                   locale: Locale = .autoupdatingCurrent) -> [Int: String] {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("LLL")

        var labels: [Int: String] = [:]
        var lastMonth = -1
        var lastLabelledColumn = -2
        for (index, day) in days.enumerated() {
            guard let day else { continue }
            let column = index / 7
            let month = calendar.calendar.component(.month, from: calendar.dayStart(for: day.dayKey))
            if month != lastMonth {
                lastMonth = month
                if column - lastLabelledColumn >= 3 {
                    labels[column] = formatter.string(from: calendar.dayStart(for: day.dayKey))
                    lastLabelledColumn = column
                }
            }
        }
        return labels
    }
}
