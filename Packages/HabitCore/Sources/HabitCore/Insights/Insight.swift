import Foundation

/// One observation about the person's history. Wording is deliberately associative
/// ("more often on days when"), never causal — the data cannot support causation.
public struct Insight: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable {
        /// This week's completion rate vs the previous week.
        case weeklyTrend
        /// One weekday is clearly worse than the rest.
        case weakWeekday
        /// Habit A is completed much more often on days when habit B was completed.
        case pairing
        /// An automatic habit almost reaches its goal but rarely crosses it.
        case nearMiss
        /// The hour of day this habit is usually completed.
        case typicalTime
        /// A goal changed by adaptation (or an adaptation is available).
        case goalChanged
    }

    public var kind: Kind
    public var habitID: UUID?
    public var relatedHabitID: UUID?
    /// Sorted descending; higher means "show this first".
    public var priority: Int
    /// Numbers the UI formats into localized text. Kept separate from wording so the
    /// engine stays free of user-facing strings.
    public var primaryValue: Double
    public var secondaryValue: Double
    public var sampleDays: Int
    /// Calendar weekday 1…7 for `weakWeekday`, hour 0…23 for `typicalTime`.
    public var unitLabel: String

    public var id: String {
        [kind.rawValue, habitID?.uuidString ?? "-", relatedHabitID?.uuidString ?? "-"].joined(separator: ":")
    }

    public init(kind: Kind, habitID: UUID? = nil, relatedHabitID: UUID? = nil, priority: Int,
                primaryValue: Double = 0, secondaryValue: Double = 0, sampleDays: Int = 0, unitLabel: String = "") {
        self.kind = kind
        self.habitID = habitID
        self.relatedHabitID = relatedHabitID
        self.priority = priority
        self.primaryValue = primaryValue
        self.secondaryValue = secondaryValue
        self.sampleDays = sampleDays
        self.unitLabel = unitLabel
    }
}
