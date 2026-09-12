import Foundation
import SwiftData

/// One row per (habit, logical day). Holds partial progress for automatic habits.
@Model
public final class DailyLog {
    #Index<DailyLog>([\.habitID, \.dayKey])

    public var id: UUID = UUID()
    /// Denormalized for `#Predicate`; the relationship is optional for CloudKit.
    public var habitID: UUID = UUID()
    /// `yyyy-MM-dd` of the logical day.
    public var dayKey: String = ""
    /// Instant the logical day began (for reproducibility when `dayStartHour` changes).
    public var dayStart: Date = Date()
    public var timeZoneID: String = TimeZone.current.identifier
    public var progressValue: Double = 0
    /// Target snapshotted at evaluation time so history survives rule edits.
    public var targetValue: Double = 1
    public var isCompleted: Bool = false
    public var completedAt: Date? = nil
    public var completionSourceRaw: String = CompletionSource.unset.rawValue
    /// Set when the "completed automatically" notification was sent; prevents repeats.
    public var notifiedAt: Date? = nil
    public var lastEvaluatedAt: Date? = nil
    public var updatedAt: Date = Date()

    public var habit: Habit? = nil

    public init(habitID: UUID, dayKey: DayKey, dayStart: Date, targetValue: Double, timeZone: TimeZone = .current) {
        self.id = UUID()
        self.habitID = habitID
        self.dayKey = dayKey.raw
        self.dayStart = dayStart
        self.timeZoneID = timeZone.identifier
        self.targetValue = targetValue
        self.updatedAt = Date()
    }

    public var key: DayKey { DayKey(raw: dayKey) }

    public var completionSource: CompletionSource {
        get { CompletionSource(rawValue: completionSourceRaw) ?? .unset }
        set { completionSourceRaw = newValue.rawValue }
    }

    public var ratio: Double {
        guard targetValue > 0 else { return isCompleted ? 1 : 0 }
        return min(max(progressValue / targetValue, 0), 1)
    }
}
