import Foundation
import SwiftData

@MainActor
public final class SwiftDataHabitRepository: HabitRepository {
    public let context: ModelContext
    /// Kept so the container outlives the repository: a `ModelContext` does not retain its
    /// container, and inserting into a context whose container has been deallocated traps.
    private let container: ModelContainer?

    public init(context: ModelContext, container: ModelContainer? = nil) {
        self.context = context
        self.container = container
    }

    public convenience init(container: ModelContainer) {
        self.init(context: container.mainContext, container: container)
    }

    // MARK: Habits

    public func activeHabits() throws -> [Habit] {
        let descriptor = FetchDescriptor<Habit>(
            predicate: #Predicate { $0.archivedAt == nil },
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        )
        return try context.fetch(descriptor)
    }

    public func allHabits(includeArchived: Bool) throws -> [Habit] {
        if !includeArchived { return try activeHabits() }
        let descriptor = FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)])
        return try context.fetch(descriptor)
    }

    public func habit(id: UUID) throws -> Habit? {
        var descriptor = FetchDescriptor<Habit>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    // MARK: Logs

    public func logs(habitID: UUID, from: DayKey, to: DayKey) throws -> [DailyLog] {
        let descriptor = FetchDescriptor<DailyLog>(predicate: #Predicate { $0.habitID == habitID })
        // String range comparison inside #Predicate is unreliable; per-habit log counts are small.
        return try context.fetch(descriptor)
            .filter { $0.dayKey >= from.raw && $0.dayKey <= to.raw }
            .sorted { $0.dayKey < $1.dayKey }
    }

    public func logs(dayKey: DayKey) throws -> [DailyLog] {
        let raw = dayKey.raw
        let descriptor = FetchDescriptor<DailyLog>(predicate: #Predicate { $0.dayKey == raw })
        return try context.fetch(descriptor)
    }

    public func logs(from: DayKey, to: DayKey) throws -> [DailyLog] {
        // String range comparison inside #Predicate is unreliable; filter in memory.
        try context.fetch(FetchDescriptor<DailyLog>())
            .filter { $0.dayKey >= from.raw && $0.dayKey <= to.raw }
    }

    public func log(habitID: UUID, dayKey: DayKey) throws -> DailyLog? {
        let raw = dayKey.raw
        var descriptor = FetchDescriptor<DailyLog>(
            predicate: #Predicate { $0.habitID == habitID && $0.dayKey == raw },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func fetchOrCreateLog(habitID: UUID, dayKey: DayKey, dayStart: Date, target: Double) throws -> DailyLog {
        if let existing = try log(habitID: habitID, dayKey: dayKey) { return existing }
        let log = DailyLog(habitID: habitID, dayKey: dayKey, dayStart: dayStart, targetValue: target)
        log.habit = try habit(id: habitID)
        context.insert(log)
        return log
    }

    // MARK: Visits

    public func visits(habitID: UUID, overlapping window: DateInterval, now: Date) throws -> [GeofenceVisit] {
        let descriptor = FetchDescriptor<GeofenceVisit>(
            predicate: #Predicate { $0.habitID == habitID },
            sortBy: [SortDescriptor(\.enteredAt)]
        )
        return try context.fetch(descriptor).filter { $0.interval(now: now).intersects(window) }
    }

    public func openVisit(habitID: UUID) throws -> GeofenceVisit? {
        var descriptor = FetchDescriptor<GeofenceVisit>(
            predicate: #Predicate { $0.habitID == habitID && $0.exitedAt == nil },
            sortBy: [SortDescriptor(\.enteredAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func openVisits(enteredBefore: Date) throws -> [GeofenceVisit] {
        let descriptor = FetchDescriptor<GeofenceVisit>(
            predicate: #Predicate { $0.exitedAt == nil && $0.enteredAt < enteredBefore }
        )
        return try context.fetch(descriptor)
    }

    // MARK: Mutation

    public func insert(_ model: any PersistentModel) { context.insert(model) }
    public func delete(_ model: any PersistentModel) { context.delete(model) }

    public func save() throws {
        if context.hasChanges { try context.save() }
    }

    public func changed(since: Date) throws -> ChangedRecords {
        let habits = try context.fetch(FetchDescriptor<Habit>(predicate: #Predicate { $0.updatedAt > since }))
        let logs = try context.fetch(FetchDescriptor<DailyLog>(predicate: #Predicate { $0.updatedAt > since }))
        return ChangedRecords(habitIDs: habits.map(\.id), logIDs: logs.map(\.id))
    }
}
