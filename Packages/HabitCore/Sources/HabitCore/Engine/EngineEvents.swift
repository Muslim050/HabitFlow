import Foundation

/// Emitted once per (habit, day) when the engine flips a log to completed automatically.
public struct CompletionEvent: Sendable, Equatable {
    public var habitID: UUID
    public var habitName: String
    public var emoji: String
    public var dayKey: DayKey
    public var value: Double
    public var target: Double
    public var unitLabel: String
    public var sourceLabel: String
    public var reason: EvaluationReason

    public init(habitID: UUID, habitName: String, emoji: String, dayKey: DayKey, value: Double, target: Double,
                unitLabel: String, sourceLabel: String, reason: EvaluationReason) {
        self.habitID = habitID
        self.habitName = habitName
        self.emoji = emoji
        self.dayKey = dayKey
        self.value = value
        self.target = target
        self.unitLabel = unitLabel
        self.sourceLabel = sourceLabel
        self.reason = reason
    }
}

public struct EvaluationSummary: Sendable {
    public var evaluatedHabitIDs: [UUID] = []
    public var completions: [CompletionEvent] = []
    public var failures: [UUID: String] = [:]
    public init() {}
}
