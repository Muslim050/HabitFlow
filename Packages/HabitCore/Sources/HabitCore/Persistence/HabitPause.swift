import Foundation
import SwiftData

/// A holiday, an illness, or a deliberate break. `habitID == nil` pauses everything at once —
/// the global off switch — so one shape covers both cases and the resolver merges them.
///
/// CloudKit-safe: every stored property has a default and nothing is unique.
@Model
public final class HabitPause {
    public var id: UUID = UUID()
    /// `nil` means every habit.
    public var habitID: UUID? = nil
    /// `yyyy-MM-dd` of the first paused day.
    public var startDayKey: String = ""
    /// `yyyy-MM-dd` of the last paused day; empty while the pause is still running.
    public var endDayKey: String = ""
    public var reasonRaw: String = PauseReason.other.rawValue
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public init(habitID: UUID?, start: DayKey, end: DayKey? = nil,
                reason: PauseReason = .other, createdAt: Date = Date()) {
        self.id = UUID()
        self.habitID = habitID
        self.startDayKey = start.raw
        self.endDayKey = end?.raw ?? ""
        self.reasonRaw = reason.rawValue
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    public var reason: PauseReason {
        get { PauseReason(rawValue: reasonRaw) ?? .other }
        set { reasonRaw = newValue.rawValue; updatedAt = Date() }
    }

    public var span: PauseSpan {
        PauseSpan(start: DayKey(raw: startDayKey),
                  end: endDayKey.isEmpty ? nil : DayKey(raw: endDayKey),
                  reason: reason)
    }

    public var isGlobal: Bool { habitID == nil }
    public var isRunning: Bool { endDayKey.isEmpty }

    /// Ends a running pause on `key`, which is how "resume now" is expressed.
    public func end(on key: DayKey) {
        endDayKey = key.raw
        updatedAt = Date()
    }
}

public extension Collection where Element == HabitPause {
    /// This habit's own pauses plus every global one, as day spans.
    func spans(for habitID: UUID) -> [PauseSpan] {
        compactMap { $0.habitID == nil || $0.habitID == habitID ? $0.span : nil }
    }

    var globalSpans: [PauseSpan] { compactMap { $0.habitID == nil ? $0.span : nil } }
}
