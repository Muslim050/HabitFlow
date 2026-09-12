import Foundation

/// What the composer collects before anything is written. Kept free of EventKit so the
/// rules can be tested, and so the app decides once where a draft actually lands.
public struct AgendaDraft: Sendable, Equatable, Identifiable {
    public enum Repeat: String, CaseIterable, Sendable, Identifiable {
        case never, daily, weekdays, weekly
        public var id: String { rawValue }
    }

    public var kind: AgendaItem.Kind
    public var title: String
    /// Event start, or a reminder's due moment.
    public var date: Date
    /// Reminders may have no time at all; events always do.
    public var hasTime: Bool
    public var durationMinutes: Int
    public var repeats: Repeat
    /// Calendar or reminder list to write into; `nil` means the system default.
    public var containerID: String?

    public static let durations = [15, 30, 45, 60, 90, 120]

    public init(kind: AgendaItem.Kind = .event, title: String = "", date: Date = Date(),
                hasTime: Bool = true, durationMinutes: Int = 60,
                repeats: Repeat = .never, containerID: String? = nil) {
        self.kind = kind
        self.title = title
        self.date = date
        self.hasTime = hasTime
        self.durationMinutes = durationMinutes
        self.repeats = repeats
        self.containerID = containerID
    }

    /// Only for `sheet(item:)`; a draft is a value, not a stored thing.
    public var id: String { "\(kind.rawValue)-\(title)-\(date.timeIntervalSince1970)" }

    public var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    public var isValid: Bool { !trimmedTitle.isEmpty && durationMinutes > 0 }

    public var endDate: Date { date.addingTimeInterval(TimeInterval(durationMinutes * 60)) }

    /// Weekdays (1 = Sunday) the repeat covers, or `nil` when the rule needs no day list.
    public func weekdays(calendar: Calendar = .current) -> [Int]? {
        switch repeats {
        case .never, .daily: return nil
        case .weekdays: return [2, 3, 4, 5, 6]
        case .weekly: return [calendar.component(.weekday, from: date)]
        }
    }

    /// Rounds to the next quarter hour so a freshly opened composer never offers 14:07.
    public static func nextQuarterHour(after now: Date = Date(), calendar: Calendar = .current) -> Date {
        let minutes = calendar.component(.minute, from: now)
        let bump = 15 - (minutes % 15)
        let rounded = calendar.date(byAdding: .minute, value: bump == 15 ? 15 : bump, to: now) ?? now
        return calendar.date(bySetting: .second, value: 0, of: rounded) ?? rounded
    }
}

/// Turns what the app already knows about a habit into a filled-in draft. This is the part
/// the system Calendar cannot do: it does not know when you actually close this habit.
public enum HabitSchedulingSuggestion {

    public struct Result: Sendable, Equatable {
        public var draft: AgendaDraft
        /// True when the time came from real completions rather than a fallback.
        public var fromHistory: Bool
        /// Completions the hour was derived from.
        public var sampleCount: Int
    }

    public static let minimumCompletions = 4

    public static func suggest(habit: Habit, logs: [DailyLog], calendar: DayCalendar,
                               now: Date = Date(), fallbackHour: Int = 20,
                               kind: AgendaItem.Kind = .event) -> Result {
        let hours = logs
            .filter { $0.habitID == habit.id && $0.isCompleted }
            .compactMap(\.completedAt)
            .map { date -> Double in
                let parts = calendar.calendar.dateComponents([.hour, .minute], from: date)
                return Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60
            }

        let fromHistory = hours.count >= minimumCompletions
        let hour = fromHistory ? GoalAdaptation.medianOf(hours) : Double(fallbackHour)

        // Tomorrow if today's slot has gone, so the suggestion is always actionable.
        var components = calendar.calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = Int(hour)
        components.minute = Int((hour - Double(Int(hour))) * 60 / 15) * 15
        var date = calendar.calendar.date(from: components) ?? now
        if date <= now {
            date = calendar.calendar.date(byAdding: .day, value: 1, to: date) ?? date
        }

        let draft = AgendaDraft(
            kind: kind,
            title: habit.name,
            date: date,
            hasTime: true,
            durationMinutes: suggestedDuration(for: habit),
            repeats: habit.scheduleMask == Habit.everyDayMask ? .daily : .weekly
        )
        return Result(draft: draft, fromHistory: fromHistory, sampleCount: hours.count)
    }

    /// A place habit already states how long you mean to stay; everything else gets an hour.
    static func suggestedDuration(for habit: Habit) -> Int {
        switch habit.rule {
        case .geofence(_, _, _, let minutes, _): return max(15, Int(minutes))
        case .healthWorkout(_, let minutes): return max(15, Int(minutes))
        case .healthMindful(let minutes): return max(15, Int(minutes))
        default: return 60
        }
    }
}
