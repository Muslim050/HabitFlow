import Foundation
import SwiftData

public struct ChangedRecords: Sendable {
    public var habitIDs: [UUID]
    public var logIDs: [UUID]
}

/// The only persistence boundary the engine and view models talk to.
/// A future backend sync service plugs in here (diff by `updatedAt`).
@MainActor
public protocol HabitRepository: AnyObject {
    func activeHabits() throws -> [Habit]
    func allHabits(includeArchived: Bool) throws -> [Habit]
    func habit(id: UUID) throws -> Habit?

    func logs(habitID: UUID, from: DayKey, to: DayKey) throws -> [DailyLog]
    func logs(dayKey: DayKey) throws -> [DailyLog]
    /// Every habit's logs in the range, for cross-habit analysis.
    func logs(from: DayKey, to: DayKey) throws -> [DailyLog]
    func log(habitID: UUID, dayKey: DayKey) throws -> DailyLog?
    func fetchOrCreateLog(habitID: UUID, dayKey: DayKey, dayStart: Date, target: Double) throws -> DailyLog

    /// Every pause, global and per-habit. There are a handful at most, so callers filter in
    /// memory with `spans(for:)` rather than building a predicate over an optional id.
    func pauses() throws -> [HabitPause]

    func visits(habitID: UUID, overlapping window: DateInterval, now: Date) throws -> [GeofenceVisit]
    func openVisit(habitID: UUID) throws -> GeofenceVisit?
    func openVisits(enteredBefore: Date) throws -> [GeofenceVisit]

    func insert(_ model: any PersistentModel)
    func delete(_ model: any PersistentModel)
    func save() throws

    func changed(since: Date) throws -> ChangedRecords
}
