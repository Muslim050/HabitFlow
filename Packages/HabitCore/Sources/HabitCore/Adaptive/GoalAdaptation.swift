import Foundation

public enum GoalAdaptationMode: String, Codable, CaseIterable, Sendable {
    /// Goal never changes on its own.
    case off
    /// A proposal is shown; the user applies it.
    case suggest
    /// The engine applies the change and tells the user afterwards.
    case automatic
}

public struct GoalProposal: Sendable, Equatable, Identifiable {
    public enum Direction: String, Sendable { case increase, decrease }

    public var habitID: UUID
    public var direction: Direction
    public var currentTarget: Double
    public var proposedTarget: Double
    public var unitLabel: String
    /// Share of scheduled days completed in the window, 0…1.
    public var completionRate: Double
    /// Median achieved value in the window (raw, not clamped to the target).
    public var medianValue: Double
    public var sampleDays: Int

    public var id: UUID { habitID }

    public init(habitID: UUID, direction: Direction, currentTarget: Double, proposedTarget: Double,
                unitLabel: String, completionRate: Double, medianValue: Double, sampleDays: Int) {
        self.habitID = habitID
        self.direction = direction
        self.currentTarget = currentTarget
        self.proposedTarget = proposedTarget
        self.unitLabel = unitLabel
        self.completionRate = completionRate
        self.medianValue = medianValue
        self.sampleDays = sampleDays
    }
}

/// Decides when a habit's goal should grow or shrink, from what the person actually achieved.
/// Pure and fully tested; the engine only applies the result.
public enum GoalAdaptation {
    public static let windowDays = 14
    public static let minimumSampleDays = 10
    /// Days that must pass after a change (or a dismissal) before proposing again.
    public static let cooldownDays = 14

    public static let increaseCompletionRate = 0.85
    public static let increaseMedianRatio = 1.10
    public static let decreaseCompletionRate = 0.40
    public static let decreaseMedianRatio = 0.80
    /// One adaptation never moves the goal by more than this share of the current target.
    public static let maxStepShare = 0.50

    /// `samples` are the habit's scheduled days in the window, oldest first:
    /// achieved value and whether the day counted as completed.
    public struct DaySample: Sendable, Equatable {
        public var value: Double
        public var completed: Bool
        public init(value: Double, completed: Bool) {
            self.value = value
            self.completed = completed
        }
    }

    public static func proposal(
        habitID: UUID,
        rule: HabitRule,
        samples: [DaySample],
        mode: GoalAdaptationMode,
        lastChangeAt: Date?,
        lastDismissedAt: Date?,
        now: Date,
        calendar: Calendar = .current
    ) -> GoalProposal? {
        guard mode != .off else { return nil }
        guard rule.withTarget(rule.target) != nil, rule.target > 0, rule.goalStep > 0 else { return nil }
        guard samples.count >= minimumSampleDays else { return nil }
        guard !isInCooldown(lastChangeAt: lastChangeAt, lastDismissedAt: lastDismissedAt, now: now, calendar: calendar) else { return nil }

        let window = Array(samples.suffix(windowDays))
        let completionRate = Double(window.filter(\.completed).count) / Double(window.count)
        let median = medianOf(window.map(\.value))
        let target = rule.target
        let medianRatio = median / target

        let direction: GoalProposal.Direction
        if completionRate >= increaseCompletionRate && medianRatio >= increaseMedianRatio {
            direction = .increase
        } else if completionRate <= decreaseCompletionRate && medianRatio <= decreaseMedianRatio {
            direction = .decrease
        } else {
            return nil
        }

        guard let proposed = proposedTarget(direction: direction, median: median, rule: rule) else { return nil }
        return GoalProposal(
            habitID: habitID, direction: direction, currentTarget: target, proposedTarget: proposed,
            unitLabel: rule.unitLabel, completionRate: completionRate, medianValue: median, sampleDays: window.count
        )
    }

    static func isInCooldown(lastChangeAt: Date?, lastDismissedAt: Date?, now: Date, calendar: Calendar) -> Bool {
        let anchors = [lastChangeAt, lastDismissedAt].compactMap { $0 }
        guard let latest = anchors.max() else { return false }
        guard let ready = calendar.date(byAdding: .day, value: cooldownDays, to: latest) else { return false }
        return now < ready
    }

    /// Aim just under (or just over) what the person actually does, snapped to the rule's step.
    static func proposedTarget(direction: GoalProposal.Direction, median: Double, rule: HabitRule) -> Double? {
        let step = rule.goalStep
        let target = rule.target
        let maxDelta = max(step, (target * maxStepShare / step).rounded(.down) * step)

        let raw: Double
        switch direction {
        case .increase: raw = median * 0.95
        case .decrease: raw = median * 1.05
        }
        var proposed = (raw / step).rounded() * step

        switch direction {
        case .increase:
            proposed = min(max(proposed, target + step), target + maxDelta)
        case .decrease:
            proposed = max(min(proposed, target - step), target - maxDelta)
            proposed = max(proposed, rule.goalFloor)
        }
        proposed = (proposed / step).rounded() * step
        guard proposed != target, proposed > 0 else { return nil }
        guard direction == .increase ? proposed > target : proposed < target else { return nil }
        return proposed
    }

    static func medianOf(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
