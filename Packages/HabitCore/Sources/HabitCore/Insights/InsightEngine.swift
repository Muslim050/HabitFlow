import Foundation

/// Finds patterns in completion history. Every rule has a minimum sample size and a minimum
/// effect size, so a couple of lucky days never produce a claim.
public enum InsightEngine {
    // Thresholds, all deliberately conservative.
    public static let trendMinDaysPerWeek = 4
    public static let trendMinDelta = 0.20

    public static let weekdayWindowDays = 56
    public static let weekdayMinOccurrences = 4
    public static let weekdayMinGap = 0.25

    public static let pairingWindowDays = 60
    public static let pairingMinOverlapDays = 12
    public static let pairingMinGroupDays = 5
    public static let pairingMinGap = 0.25

    public static let nearMissWindowDays = 21
    public static let nearMissMinDays = 10
    public static let nearMissMaxCompletionRate = 0.50
    public static let nearMissMinRatio = 0.85

    public static let typicalTimeMinCompletions = 6
    /// Times must be tight enough to be worth mentioning (interquartile range in hours).
    public static let typicalTimeMaxSpreadHours = 3.0

    /// Ordering bands: something to act on first, then relationships, then timing, then trivia.
    enum Priority {
        static let nearMiss = 90
        static let pairing = 70
        static let weakWeekday = 55
        static let weeklyTrend = 40
        static let typicalTime = 30
    }

    /// One habit's day: what happened and, for automatic habits, how much was achieved.
    public struct DayFact: Sendable, Equatable {
        public var dayKey: DayKey
        public var scheduled: Bool
        public var completed: Bool
        /// achieved / target, unclamped. 0 for manual habits that were not done.
        public var ratio: Double
        /// Hour of day (0…23, fractional) when it was completed, if known.
        public var completedHour: Double?

        public init(dayKey: DayKey, scheduled: Bool, completed: Bool, ratio: Double, completedHour: Double? = nil) {
            self.dayKey = dayKey
            self.scheduled = scheduled
            self.completed = completed
            self.ratio = ratio
            self.completedHour = completedHour
        }
    }

    /// Everything the engine needs about one habit, oldest day first.
    public struct HabitHistory: Sendable {
        public var habitID: UUID
        public var isAutomatic: Bool
        public var unitLabel: String
        public var facts: [DayFact]

        public init(habitID: UUID, isAutomatic: Bool, unitLabel: String, facts: [DayFact]) {
            self.habitID = habitID
            self.isAutomatic = isAutomatic
            self.unitLabel = unitLabel
            self.facts = facts
        }
    }

    public static func insights(for histories: [HabitHistory], calendar: DayCalendar, today: DayKey, limit: Int = 6) -> [Insight] {
        var found: [Insight] = []
        for history in histories {
            if let insight = weeklyTrend(history, calendar: calendar, today: today) { found.append(insight) }
            if let insight = weakWeekday(history, calendar: calendar, today: today) { found.append(insight) }
            if let insight = nearMiss(history, today: today) { found.append(insight) }
            if let insight = typicalTime(history, today: today) { found.append(insight) }
        }
        found.append(contentsOf: pairings(histories, today: today))
        return Array(found.sorted { $0.priority > $1.priority }.prefix(limit))
    }

    // MARK: Week over week

    static func weeklyTrend(_ history: HabitHistory, calendar: DayCalendar, today: DayKey) -> Insight? {
        // Yesterday backwards, so a day still in progress cannot look like a miss.
        let scheduled = history.facts.filter { $0.scheduled && $0.dayKey < today }
        guard scheduled.count >= trendMinDaysPerWeek * 2 else { return nil }
        let lastSeven = Array(scheduled.suffix(7))
        let previousSeven = Array(scheduled.dropLast(7).suffix(7))
        guard lastSeven.count >= trendMinDaysPerWeek, previousSeven.count >= trendMinDaysPerWeek else { return nil }

        let current = rate(lastSeven)
        let previous = rate(previousSeven)
        let delta = current - previous
        guard abs(delta) >= trendMinDelta else { return nil }
        return Insight(
            kind: .weeklyTrend, habitID: history.habitID,
            priority: Priority.weeklyTrend + Int(abs(delta) * 10),
            primaryValue: current, secondaryValue: previous,
            sampleDays: lastSeven.count + previousSeven.count
        )
    }

    // MARK: Weak weekday

    static func weakWeekday(_ history: HabitHistory, calendar: DayCalendar, today: DayKey) -> Insight? {
        let window = history.facts.filter { $0.scheduled && $0.dayKey < today }.suffix(weekdayWindowDays)
        guard window.count >= weekdayMinOccurrences * 3 else { return nil }

        var byWeekday: [Int: [DayFact]] = [:]
        for fact in window {
            byWeekday[calendar.weekday(for: fact.dayKey), default: []].append(fact)
        }
        let eligible = byWeekday.filter { $0.value.count >= weekdayMinOccurrences }
        guard eligible.count >= 3 else { return nil }

        let overall = rate(Array(window))
        guard overall > 0 else { return nil }
        guard let worst = eligible.min(by: { rate($0.value) < rate($1.value) }) else { return nil }
        let worstRate = rate(worst.value)
        // Compare against the other days, not the mixed average, so the gap is not diluted.
        let others = eligible.filter { $0.key != worst.key }.flatMap(\.value)
        let othersRate = rate(others)
        guard othersRate - worstRate >= weekdayMinGap else { return nil }

        return Insight(
            kind: .weakWeekday, habitID: history.habitID,
            priority: Priority.weakWeekday + Int((othersRate - worstRate) * 10),
            primaryValue: Double(worst.key), secondaryValue: worstRate,
            sampleDays: worst.value.count
        )
    }

    // MARK: Pairing between two habits

    static func pairings(_ histories: [HabitHistory], today: DayKey) -> [Insight] {
        guard histories.count >= 2 else { return [] }
        var result: [Insight] = []
        for (indexA, a) in histories.enumerated() {
            for b in histories[(indexA + 1)...] {
                if let insight = pairing(target: a, condition: b, today: today) { result.append(insight) }
                if let insight = pairing(target: b, condition: a, today: today) { result.append(insight) }
            }
        }
        return result
    }

    static func pairing(target: HabitHistory, condition: HabitHistory, today: DayKey) -> Insight? {
        let conditionByDay = Dictionary(
            condition.facts.filter { $0.scheduled }.map { ($0.dayKey, $0.completed) },
            uniquingKeysWith: { first, _ in first }
        )
        let overlap = target.facts
            .filter { $0.scheduled && $0.dayKey < today && conditionByDay[$0.dayKey] != nil }
            .suffix(pairingWindowDays)
        guard overlap.count >= pairingMinOverlapDays else { return nil }

        let withCondition = overlap.filter { conditionByDay[$0.dayKey] == true }
        let withoutCondition = overlap.filter { conditionByDay[$0.dayKey] == false }
        guard withCondition.count >= pairingMinGroupDays, withoutCondition.count >= pairingMinGroupDays else { return nil }

        let withRate = rate(Array(withCondition))
        let withoutRate = rate(Array(withoutCondition))
        guard withRate - withoutRate >= pairingMinGap else { return nil }

        return Insight(
            kind: .pairing, habitID: target.habitID, relatedHabitID: condition.habitID,
            priority: Priority.pairing + Int((withRate - withoutRate) * 15),
            primaryValue: withRate, secondaryValue: withoutRate,
            sampleDays: overlap.count
        )
    }

    // MARK: Near miss

    static func nearMiss(_ history: HabitHistory, today: DayKey) -> Insight? {
        guard history.isAutomatic else { return nil }
        let window = history.facts.filter { $0.scheduled && $0.dayKey < today }.suffix(nearMissWindowDays)
        guard window.count >= nearMissMinDays else { return nil }
        let completionRate = rate(Array(window))
        guard completionRate <= nearMissMaxCompletionRate else { return nil }
        let median = GoalAdaptation.medianOf(window.map(\.ratio))
        guard median >= nearMissMinRatio, median < 1 else { return nil }

        return Insight(
            kind: .nearMiss, habitID: history.habitID,
            priority: Priority.nearMiss,
            primaryValue: median, secondaryValue: completionRate,
            sampleDays: window.count, unitLabel: history.unitLabel
        )
    }

    // MARK: Typical time of day

    static func typicalTime(_ history: HabitHistory, today: DayKey) -> Insight? {
        let hours = history.facts
            .filter { $0.completed && $0.dayKey < today }
            .compactMap(\.completedHour)
        guard hours.count >= typicalTimeMinCompletions else { return nil }
        let sorted = hours.sorted()
        let median = GoalAdaptation.medianOf(sorted)
        let lower = sorted[max(0, Int(Double(sorted.count) * 0.25) - 0)]
        let upper = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.75))]
        guard upper - lower <= typicalTimeMaxSpreadHours else { return nil }

        return Insight(
            kind: .typicalTime, habitID: history.habitID,
            priority: Priority.typicalTime,
            primaryValue: median, sampleDays: hours.count
        )
    }

    // MARK: Helpers

    static func rate(_ facts: [DayFact]) -> Double {
        guard !facts.isEmpty else { return 0 }
        return Double(facts.filter(\.completed).count) / Double(facts.count)
    }
}
