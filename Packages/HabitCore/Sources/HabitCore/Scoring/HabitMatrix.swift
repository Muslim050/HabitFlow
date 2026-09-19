import Foundation

/// What one habit did on one day.
public enum MatrixState: Sendable, Equatable {
    /// Not due, and nothing done. Never a failure.
    case off
    /// Still to come. A calendar week runs to Sunday, so showing it while it is Saturday means
    /// drawing days that have not happened — and a day that has not happened is not a miss.
    case upcoming
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

    /// `days` counts back from today inclusive: 7 is the last seven days, 14 a fortnight.
    public static func build(habits: [Habit], logs: [DailyLog], calendar: DayCalendar,
                             today: DayKey, days dayCount: Int, pauses: [HabitPause] = []) -> HabitMatrix {
        guard dayCount > 0 else { return .empty }
        return build(habits: habits, logs: logs, calendar: calendar, today: today,
                     from: calendar.key(byAdding: -(dayCount - 1), to: today),
                     to: today, pauses: pauses)
    }

    /// Whole calendar weeks, ending with the week `today` falls in. A rolling seven days would
    /// start on whatever weekday it happens to be, which reads as a bug next to a real calendar.
    public static func build(habits: [Habit], logs: [DailyLog], calendar: DayCalendar,
                             today: DayKey, weeks: Int, pauses: [HabitPause] = []) -> HabitMatrix {
        guard weeks > 0 else { return .empty }
        let thisWeek = calendar.startOfWeek(for: today)
        let start = calendar.key(byAdding: -7 * (weeks - 1), to: thisWeek)
        let end = calendar.key(byAdding: 7 * weeks - 1, to: start)
        return build(habits: habits, logs: logs, calendar: calendar, today: today,
                     from: start, to: end, pauses: pauses)
    }

    public static func build(habits: [Habit], logs: [DailyLog], calendar: DayCalendar,
                             today: DayKey, from: DayKey, to: DayKey,
                             pauses: [HabitPause] = []) -> HabitMatrix {
        guard from <= to, !habits.isEmpty else { return .empty }
        let keys = calendar.keys(from: from, to: to)

        // (habit, day) -> log, so a habit with no row for a day is simply absent.
        let logByHabitDay = logs.reduce(into: [UUID: [String: DailyLog]]()) { map, log in
            map[log.habitID, default: [:]][log.dayKey] = log
        }

        let rows = habits.map { habit -> Row in
            // The resolver already refuses days before the habit existed, however the schedule reads.
            let resolver = ScheduleResolver(habit: habit, calendar: calendar, pauses: pauses.spans(for: habit.id))
            var states: [MatrixState] = []
            var done = 0
            for key in keys {
                guard key <= today else {
                    states.append(.upcoming)
                    continue
                }
                let log = logByHabitDay[habit.id]?[key.raw]
                if log?.isCompleted == true {
                    done += 1
                    states.append(.done)
                    continue
                }
                switch resolver.obligation(on: key) {
                case .off, .flexible, .paused:
                    // A quota habit owes the week, not this day: an unused day is not a miss.
                    // A paused day is asked for nothing at all.
                    states.append(.off)
                case .required:
                    let ratio = log?.ratio ?? 0
                    states.append(ratio > 0 ? .partial(ratio) : .missed)
                }
            }
            // Prorated so a quota habit shows "2 / 3 this week", not "2 / 7".
            let last = min(keys.last ?? today, today)
            let scheduled = keys.isEmpty || keys[0] > last ? 0 : resolver.demand(from: keys[0], to: last)
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

    /// `taken` are the colours already in use. A preset keeps its own recognisable colour when
    /// it is free and steps aside when it is not — two habits sharing a colour makes the month
    /// grid's stripes impossible to tell apart.
    public func makeHabit(sortOrder: Int, taken: some Collection<String> = [String]()) -> Habit {
        let used = Set(taken.map { $0.uppercased() })
        let colour = used.contains(colorHex.uppercased()) ? HabitPalette.next(after: taken) : colorHex
        return Habit(name: title, emoji: emoji, colorHex: colour, rule: rule, sortOrder: sortOrder)
    }
}
