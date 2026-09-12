import Foundation

/// What one habit did on one day.
public enum MatrixState: Sendable, Equatable {
    /// Not due, and nothing done. Never a failure.
    case off
    /// Due, nothing recorded.
    case missed
    /// Due, some progress: 0 < ratio < 1.
    case partial(Double)
    case done
}

/// Habits down the side, days across the top. Answers "which habit, and when" — the thing a
/// single combined grid cannot say.
public struct HabitMatrix: Sendable, Equatable {

    public struct Row: Sendable, Equatable, Identifiable {
        public var id: UUID
        public var name: String
        public var emoji: String
        public var colorHex: String
        /// One entry per day in `days`, same order.
        public var states: [MatrixState]
        public var doneCount: Int
        public var scheduledCount: Int

        public init(id: UUID, name: String, emoji: String, colorHex: String,
                    states: [MatrixState], doneCount: Int, scheduledCount: Int) {
            self.id = id
            self.name = name
            self.emoji = emoji
            self.colorHex = colorHex
            self.states = states
            self.doneCount = doneCount
            self.scheduledCount = scheduledCount
        }
    }

    /// Ascending, ending on today.
    public var days: [DayKey]
    public var rows: [Row]

    public static let empty = HabitMatrix(days: [], rows: [])

    public init(days: [DayKey], rows: [Row]) {
        self.days = days
        self.rows = rows
    }

    /// `days` counts back from today inclusive: 7 is this week so far, 14 is a fortnight.
    public static func build(habits: [Habit], logs: [DailyLog], calendar: DayCalendar,
                             today: DayKey, days dayCount: Int) -> HabitMatrix {
        guard dayCount > 0, !habits.isEmpty else { return .empty }
        let keys = calendar.keys(from: calendar.key(byAdding: -(dayCount - 1), to: today), to: today)

        // (habit, day) -> log, so a habit with no row for a day is simply absent.
        let logByHabitDay = logs.reduce(into: [UUID: [String: DailyLog]]()) { map, log in
            map[log.habitID, default: [:]][log.dayKey] = log
        }

        let rows = habits.map { habit -> Row in
            let createdDay = calendar.dayKey(for: habit.createdAt)
            var states: [MatrixState] = []
            var done = 0
            var scheduled = 0
            for key in keys {
                let log = logByHabitDay[habit.id]?[key.raw]
                // A habit that did not exist yet was never due, however the schedule reads.
                let isDue = key >= createdDay && habit.isScheduled(weekday: calendar.weekday(for: key))
                if log?.isCompleted == true {
                    done += 1
                    if isDue { scheduled += 1 }
                    states.append(.done)
                } else if !isDue {
                    states.append(.off)
                } else {
                    scheduled += 1
                    let ratio = log?.ratio ?? 0
                    states.append(ratio > 0 ? .partial(ratio) : .missed)
                }
            }
            return Row(id: habit.id, name: habit.name, emoji: habit.emoji,
                       colorHex: habit.colorHex, states: states,
                       doneCount: done, scheduledCount: scheduled)
        }
        return HabitMatrix(days: keys, rows: rows)
    }
}

/// Ready-made habits that can be created without typing — the only kind a widget can offer,
/// since a widget has no text input.
public enum HabitPreset: String, CaseIterable, Sendable, Identifiable {
    case steps, sleep, workout

    public var id: String { rawValue }

    public var emoji: String {
        switch self {
        case .steps: return "🚶"
        case .sleep: return "😴"
        case .workout: return "🏋️"
        }
    }

    public var title: String {
        switch self {
        case .steps: return String(localized: "Steps", bundle: .module)
        case .sleep: return String(localized: "Sleep", bundle: .module)
        case .workout: return String(localized: "Workout", bundle: .module)
        }
    }

    public var colorHex: String {
        switch self {
        case .steps: return HabitPalette.hexes[0]
        case .sleep: return HabitPalette.hexes[4]
        case .workout: return HabitPalette.hexes[2]
        }
    }

    public var rule: HabitRule {
        switch self {
        case .steps: return .healthQuantity(metric: .steps, target: HealthMetric.steps.defaultTarget)
        case .sleep: return .healthSleep(minHours: 7)
        case .workout: return .healthWorkout(activityRaw: nil, minMinutes: 30)
        }
    }

    /// Short goal line for a button, e.g. "8 000 steps".
    public var goalLabel: String {
        ValueFormatting.progressless(target: rule.target, unit: rule.unitLabel)
    }

    public func makeHabit(sortOrder: Int) -> Habit {
        Habit(name: title, emoji: emoji, colorHex: colorHex, rule: rule, sortOrder: sortOrder)
    }
}
