import Foundation

/// Turns stored logs into the pure structures the insight and adaptation engines consume.
public enum HistoryBuilder {
    public static func history(habit: Habit, logs: [DailyLog], calendar: DayCalendar, today: DayKey, windowDays: Int = 90) -> InsightEngine.HabitHistory {
        let byKey = Dictionary(logs.map { ($0.dayKey, $0) }, uniquingKeysWith: { a, b in a.updatedAt >= b.updatedAt ? a : b })
        let resolver = ScheduleResolver(habit: habit, calendar: calendar)
        let firstKey = max(calendar.dayKey(for: habit.createdAt), calendar.key(byAdding: -(windowDays - 1), to: today))
        let facts = calendar.keys(from: firstKey, to: today).map { key -> InsightEngine.DayFact in
            let log = byKey[key.raw]
            return InsightEngine.DayFact(
                dayKey: key,
                // Every due day, flexible ones included. The rules here reason about days, so a
                // weekly quota widens the denominator and mostly keeps insights below threshold —
                // period-aware insights are their own task (roadmap Stage 2).
                scheduled: resolver.obligation(on: key).isDue,
                completed: log?.isCompleted ?? false,
                ratio: rawRatio(log),
                completedHour: log?.completedAt.map { hour(of: $0, calendar: calendar.calendar) }
            )
        }
        return InsightEngine.HabitHistory(
            habitID: habit.id, isAutomatic: habit.isAutomatic, unitLabel: habit.rule.unitLabel, facts: facts
        )
    }

    /// Samples for goal adaptation: due days that actually have a log, newest last.
    ///
    /// On a flexible schedule an untouched day is not evidence the goal is too hard — the user
    /// simply chose another day — so only days with something recorded count. Without this, a
    /// "three times a week" habit would look like it fails four days out of seven and the goal
    /// would be lowered for no reason.
    public static func adaptationSamples(habit: Habit, logs: [DailyLog], calendar: DayCalendar, today: DayKey) -> [GoalAdaptation.DaySample] {
        let byKey = Dictionary(logs.map { ($0.dayKey, $0) }, uniquingKeysWith: { a, b in a.updatedAt >= b.updatedAt ? a : b })
        let resolver = ScheduleResolver(habit: habit, calendar: calendar)
        let firstKey = calendar.key(byAdding: -(GoalAdaptation.windowDays * 2), to: today)
        return calendar.keys(from: firstKey, to: today)
            .filter { $0 < today }   // today is still in progress
            .compactMap { key -> GoalAdaptation.DaySample? in
                let obligation = resolver.obligation(on: key)
                guard obligation.isDue, let log = byKey[key.raw] else { return nil }
                if obligation == .flexible && !log.isCompleted && log.progressValue <= 0 { return nil }
                return GoalAdaptation.DaySample(value: log.progressValue, completed: log.isCompleted)
            }
    }

    /// Achieved / target without the 0…1 clamp that `DailyLog.ratio` applies.
    static func rawRatio(_ log: DailyLog?) -> Double {
        guard let log else { return 0 }
        guard log.targetValue > 0 else { return log.isCompleted ? 1 : 0 }
        return log.progressValue / log.targetValue
    }

    static func hour(of date: Date, calendar: Calendar) -> Double {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        return Double(comps.hour ?? 0) + Double(comps.minute ?? 0) / 60
    }
}
