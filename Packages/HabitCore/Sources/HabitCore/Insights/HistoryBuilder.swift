import Foundation

/// Turns stored logs into the pure structures the insight and adaptation engines consume.
public enum HistoryBuilder {
    public static func history(habit: Habit, logs: [DailyLog], calendar: DayCalendar, today: DayKey, windowDays: Int = 90) -> InsightEngine.HabitHistory {
        let byKey = Dictionary(logs.map { ($0.dayKey, $0) }, uniquingKeysWith: { a, b in a.updatedAt >= b.updatedAt ? a : b })
        let firstKey = max(calendar.dayKey(for: habit.createdAt), calendar.key(byAdding: -(windowDays - 1), to: today))
        let facts = calendar.keys(from: firstKey, to: today).map { key -> InsightEngine.DayFact in
            let log = byKey[key.raw]
            return InsightEngine.DayFact(
                dayKey: key,
                scheduled: habit.isScheduled(weekday: calendar.weekday(for: key)),
                completed: log?.isCompleted ?? false,
                ratio: rawRatio(log),
                completedHour: log?.completedAt.map { hour(of: $0, calendar: calendar.calendar) }
            )
        }
        return InsightEngine.HabitHistory(
            habitID: habit.id, isAutomatic: habit.isAutomatic, unitLabel: habit.rule.unitLabel, facts: facts
        )
    }

    /// Samples for goal adaptation: scheduled days that actually have a log, newest last.
    public static func adaptationSamples(habit: Habit, logs: [DailyLog], calendar: DayCalendar, today: DayKey) -> [GoalAdaptation.DaySample] {
        let byKey = Dictionary(logs.map { ($0.dayKey, $0) }, uniquingKeysWith: { a, b in a.updatedAt >= b.updatedAt ? a : b })
        let firstKey = calendar.key(byAdding: -(GoalAdaptation.windowDays * 2), to: today)
        return calendar.keys(from: firstKey, to: today)
            .filter { $0 < today }   // today is still in progress
            .filter { habit.isScheduled(weekday: calendar.weekday(for: $0)) }
            .compactMap { key in
                guard let log = byKey[key.raw] else { return nil }
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
