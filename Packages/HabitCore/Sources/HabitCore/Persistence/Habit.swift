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
    /// Legacy weekday mask. Superseded by `scheduleData`; kept in step on every write so rows
    /// written by this build still read correctly in an older one, and so the migration from
    /// before flexible schedules has something to fall back to.
    public var scheduleMask: Int = Habit.everyDayMask
    /// Versioned JSON `HabitSchedule`. Empty on rows written before flexible schedules existed.
    public var scheduleData: Data = Data()
    public var sortOrder: Int = 0
    public var createdAt: Date = Date()
    /// Soft delete; archived habits are hidden and never evaluated.
    public var archivedAt: Date? = nil
    public var updatedAt: Date = Date()
    /// Which headline number this habit reports: strength / streak / rate / total.
    public var progressModelRaw: String = ProgressModel.default.rawValue
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
        schedule: HabitSchedule = .everyDay,
        progressModel: ProgressModel = .default,
        sortOrder: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = UUID()
        self.name = name
        self.emoji = emoji
        self.colorHex = colorHex
        self.ruleData = (try? HabitRuleCoding.encode(rule)) ?? Data()
        self.kindRaw = rule.kind.rawValue
        let schedule = schedule.normalized
        self.scheduleData = (try? HabitScheduleCoding.encode(schedule)) ?? Data()
        self.scheduleMask = schedule.legacyMask
        self.progressModelRaw = progressModel.rawValue
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

    public var progressModel: ProgressModel {
        get { ProgressModel(rawValue: progressModelRaw) ?? .default }
        set { progressModelRaw = newValue.rawValue; updatedAt = Date() }
    }

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

    public var schedule: HabitSchedule {
        get { HabitScheduleCoding.decode(scheduleData) ?? HabitSchedule.weekdays(mask: scheduleMask).normalized }
        set {
            let value = newValue.normalized
            scheduleData = (try? HabitScheduleCoding.encode(value)) ?? Data()
            scheduleMask = value.legacyMask
            updatedAt = Date()
        }
    }

    /// `pauses` must already be merged for this habit (its own plus any global ones). There is
    /// deliberately no default: forgetting them would quietly ask a paused habit for work.
    public func resolver(calendar: DayCalendar, pauses: [PauseSpan]) -> ScheduleResolver {
        ScheduleResolver(habit: self, calendar: calendar, pauses: pauses)
    }

    public func obligation(on key: DayKey, calendar: DayCalendar, pauses: [PauseSpan]) -> DayObligation {
        resolver(calendar: calendar, pauses: pauses).obligation(on: key)
    }

    /// Whether the habit can be worked on that day at all — named by the schedule, or inside a
    /// period whose quota is still open to any day, and not paused.
    public func isDue(on key: DayKey, calendar: DayCalendar, pauses: [PauseSpan]) -> Bool {
        obligation(on: key, calendar: calendar, pauses: pauses).isDue
    }
}
