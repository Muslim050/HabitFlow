import Foundation

/// How often a habit is due. Stored on `Habit` as versioned JSON, like `HabitRule`.
///
/// Two families live here and they behave differently everywhere downstream. `everyDay`,
/// `weekdays` and `everyXDays` name particular days: a named day that passes unfulfilled is a
/// miss. `timesPerWeek` and `timesPerMonth` name no day at all — they set a quota on a period,
/// and only the period can be judged. That is why scoring counts obligations, not days.
public enum HabitSchedule: Codable, Sendable, Hashable {
    case everyDay
    /// Bit `weekday - 1` set ⇒ due that weekday (bit 0 = Sunday … bit 6 = Saturday).
    case weekdays(mask: Int)
    /// Any `count` days in a calendar week, the week starting on the calendar's `firstWeekday`.
    case timesPerWeek(count: Int)
    /// Any `count` days in a calendar month.
    case timesPerMonth(count: Int)
    /// Every `interval`-th day counting from the habit's creation day.
    case everyXDays(interval: Int)

    public static let everyDayMask = 0b111_1111

    /// Clamped into ranges the rest of the code can rely on.
    public var normalized: HabitSchedule {
        switch self {
        case .everyDay: return .everyDay
        case .weekdays(let mask):
            let clean = mask & Self.everyDayMask
            return clean == Self.everyDayMask ? .everyDay : .weekdays(mask: clean)
        case .timesPerWeek(let count): return .timesPerWeek(count: min(max(count, 1), 7))
        case .timesPerMonth(let count): return .timesPerMonth(count: min(max(count, 1), 31))
        case .everyXDays(let interval):
            let clean = min(max(interval, 1), 365)
            return clean == 1 ? .everyDay : .everyXDays(interval: clean)
        }
    }

    /// The span one obligation covers. Day-based schedules judge each named day on its own.
    public var period: SchedulePeriod {
        switch self {
        case .everyDay, .weekdays, .everyXDays: return .day
        case .timesPerWeek: return .week
        case .timesPerMonth: return .month
        }
    }

    /// How many completions the period asks for; 1 for day-based schedules.
    public var quota: Int {
        switch self {
        case .everyDay, .weekdays, .everyXDays: return 1
        case .timesPerWeek(let count), .timesPerMonth(let count): return max(count, 1)
        }
    }

    /// True when the schedule leaves the choice of day to the user.
    public var isFlexible: Bool { period != .day }
}

/// The span one obligation covers.
public enum SchedulePeriod: String, Codable, Sendable, Hashable {
    case day, week, month
}

/// What a schedule asks of one particular day.
public enum DayObligation: String, Codable, Sendable, Hashable {
    /// The schedule names this day; leaving it unfulfilled is a miss.
    case required
    /// The day belongs to a period with a quota — any day in that period will do, so a single
    /// day can never be a miss on its own.
    case flexible
    /// Outside the schedule entirely.
    case off
    /// Inside a pause — a holiday, an illness, the global off switch. Not a miss, and not a day
    /// that can be kept either: the schedule asks nothing of it.
    case paused

    /// Whether the day counts towards "days the habit was live", for grids and rates.
    public var isDue: Bool { self == .required || self == .flexible }
}

// MARK: Storage

private struct HabitScheduleEnvelope: Codable {
    static let currentVersion = 1
    var v: Int
    var schedule: HabitSchedule
}

public enum HabitScheduleCoding {
    public static func encode(_ schedule: HabitSchedule) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(HabitScheduleEnvelope(v: HabitScheduleEnvelope.currentVersion, schedule: schedule))
    }

    /// `nil` for empty or unreadable data, so the caller can fall back to the legacy weekday mask
    /// instead of silently inventing a schedule.
    public static func decode(_ data: Data) -> HabitSchedule? {
        guard !data.isEmpty else { return nil }
        return (try? JSONDecoder().decode(HabitScheduleEnvelope.self, from: data))?.schedule
    }
}

public extension HabitSchedule {
    /// Best weekday-mask approximation, written alongside the JSON so an older build — or the
    /// widget between updates — still shows something sensible. Flexible schedules map to every
    /// day, which is what "any day will do" means in mask terms.
    var legacyMask: Int {
        switch normalized {
        case .everyDay, .timesPerWeek, .timesPerMonth, .everyXDays: return Self.everyDayMask
        case .weekdays(let mask): return mask
        }
    }
}
