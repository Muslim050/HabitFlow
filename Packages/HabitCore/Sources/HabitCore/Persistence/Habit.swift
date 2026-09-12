import Foundation
import SwiftData

/// CloudKit-safe: every stored property has a default, relationships are optional, no unique constraints.
@Model
public final class Habit {
    public var id: UUID = UUID()
    public var name: String = ""
    public var emoji: String = "✅"
    public var colorHex: String = "#4F8EF7"
    public var kindRaw: String = HabitSourceKind.manual.rawValue
    public var ruleData: Data = Data()
    /// Bit `weekday - 1` set ⇒ scheduled on that weekday (bit 0 = Sunday … bit 6 = Saturday).
    public var scheduleMask: Int = Habit.everyDayMask
    public var sortOrder: Int = 0
    public var createdAt: Date = Date()
    /// Soft delete; archived habits are hidden and never evaluated.
    public var archivedAt: Date? = nil
    public var updatedAt: Date = Date()
    /// How the goal may change over time: off / suggest / automatic.
    public var adaptationModeRaw: String = GoalAdaptationMode.suggest.rawValue
    /// Last time the goal was raised or lowered by adaptation (cooldown anchor).
    public var lastGoalChangeAt: Date? = nil
    /// Last time the user dismissed a proposal (so it does not nag every day).
    public var lastProposalDismissedAt: Date? = nil

    @Relationship(deleteRule: .cascade, inverse: \DailyLog.habit)
    public var logs: [DailyLog]? = []

    public static let everyDayMask = 0b111_1111

    public init(
        name: String,
        emoji: String = "✅",
        colorHex: String = "#4F8EF7",
        rule: HabitRule = .manual,
        scheduleMask: Int = Habit.everyDayMask,
        sortOrder: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = UUID()
        self.name = name
        self.emoji = emoji
        self.colorHex = colorHex
        self.ruleData = (try? HabitRuleCoding.encode(rule)) ?? Data()
        self.kindRaw = rule.kind.rawValue
        self.scheduleMask = scheduleMask
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    public var rule: HabitRule {
        get { HabitRuleCoding.decode(ruleData) }
        set {
            ruleData = (try? HabitRuleCoding.encode(newValue)) ?? Data()
            kindRaw = newValue.kind.rawValue
            updatedAt = Date()
        }
    }

    public var kind: HabitSourceKind { HabitSourceKind(rawValue: kindRaw) ?? .manual }

    public var adaptationMode: GoalAdaptationMode {
        get { GoalAdaptationMode(rawValue: adaptationModeRaw) ?? .suggest }
        set { adaptationModeRaw = newValue.rawValue; updatedAt = Date() }
    }

    /// Applies a new numeric target to the current rule and stamps the cooldown.
    public func applyGoal(_ target: Double, at date: Date = Date()) {
        guard let updated = rule.withTarget(target) else { return }
        rule = updated
        lastGoalChangeAt = date
        lastProposalDismissedAt = nil
        updatedAt = date
    }
    public var isAutomatic: Bool { kind.isAutomatic }
    public var isArchived: Bool { archivedAt != nil }

    /// `weekday` uses `Calendar` numbering: 1 = Sunday … 7 = Saturday.
    public func isScheduled(weekday: Int) -> Bool {
        guard (1...7).contains(weekday) else { return false }
        return scheduleMask & (1 << (weekday - 1)) != 0
    }

    public func setScheduled(_ scheduled: Bool, weekday: Int) {
        guard (1...7).contains(weekday) else { return }
        if scheduled { scheduleMask |= (1 << (weekday - 1)) } else { scheduleMask &= ~(1 << (weekday - 1)) }
        updatedAt = Date()
    }
}
