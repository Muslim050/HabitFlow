import Foundation

public struct ImportSummary: Sendable, Equatable {
    public var habitsInserted = 0
    public var habitsUpdated = 0
    public var logsInserted = 0
    public var logsUpdated = 0
    public var visitsInserted = 0
    public var pausesInserted = 0
    /// Records naming a habit the archive does not contain and the store does not have either.
    public var orphansSkipped = 0

    public var isEmpty: Bool {
        habitsInserted + habitsUpdated + logsInserted + logsUpdated + visitsInserted + pausesInserted == 0
    }
}

@MainActor
public enum BackupImporter {
    /// Merges an archive into the store: a record whose id is already there wins only if it is
    /// newer by `updatedAt`, anything unknown is inserted. Merging rather than replacing means
    /// importing into an empty store restores it exactly, and importing into a live one cannot
    /// silently throw away work done since the export.
    @discardableResult
    public static func merge(_ archive: BackupArchive, into repository: any HabitRepository) throws -> ImportSummary {
        var summary = ImportSummary()

        var habitsByID = Dictionary(try repository.allHabits(includeArchived: true).map { ($0.id, $0) },
                                    uniquingKeysWith: { a, _ in a })
        for record in archive.habits {
            if let existing = habitsByID[record.id] {
                guard record.updatedAt > existing.updatedAt else { continue }
                apply(record, to: existing)
                summary.habitsUpdated += 1
            } else {
                let habit = Habit(name: record.name, emoji: record.emoji, colorHex: record.colorHex,
                                  rule: record.rule, schedule: record.schedule,
                                  progressModel: record.progressModel, sortOrder: record.sortOrder,
                                  createdAt: record.createdAt)
                habit.id = record.id
                apply(record, to: habit)
                repository.insert(habit)
                habitsByID[record.id] = habit
                summary.habitsInserted += 1
            }
        }

        var logsByID = Dictionary(try repository.allLogs().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        // A second index, because two stores can hold the same (habit, day) under different ids —
        // for instance when the engine recreated a log after the export.
        var logsByDay = Dictionary(try repository.allLogs().map { ("\($0.habitID)|\($0.dayKey)", $0) },
                                   uniquingKeysWith: { a, _ in a })
        for record in archive.logs {
            guard habitsByID[record.habitID] != nil else {
                summary.orphansSkipped += 1
                continue
            }
            let dayIndex = "\(record.habitID)|\(record.dayKey)"
            if let existing = logsByID[record.id] ?? logsByDay[dayIndex] {
                guard record.updatedAt > existing.updatedAt else { continue }
                apply(record, to: existing)
                summary.logsUpdated += 1
            } else {
                let log = DailyLog(habitID: record.habitID, dayKey: DayKey(raw: record.dayKey),
                                   dayStart: record.dayStart, targetValue: record.targetValue)
                log.id = record.id
                apply(record, to: log)
                repository.insert(log)
                logsByID[record.id] = log
                logsByDay[dayIndex] = log
                summary.logsInserted += 1
            }
        }

        let visitIDs = Set(try repository.allVisits().map(\.id))
        for record in archive.visits where !visitIDs.contains(record.id) {
            guard habitsByID[record.habitID] != nil else {
                summary.orphansSkipped += 1
                continue
            }
            let visit = GeofenceVisit(habitID: record.habitID, enteredAt: record.enteredAt)
            visit.id = record.id
            visit.exitedAt = record.exitedAt
            visit.updatedAt = record.updatedAt
            repository.insert(visit)
            summary.visitsInserted += 1
        }

        let pauseIDs = Set(try repository.pauses().map(\.id))
        for record in archive.pauses where !pauseIDs.contains(record.id) {
            if let habitID = record.habitID, habitsByID[habitID] == nil {
                summary.orphansSkipped += 1
                continue
            }
            let pause = HabitPause(habitID: record.habitID, start: DayKey(raw: record.startDayKey),
                                   end: record.endDayKey.isEmpty ? nil : DayKey(raw: record.endDayKey),
                                   reason: record.reason, createdAt: record.createdAt)
            pause.id = record.id
            pause.updatedAt = record.updatedAt
            repository.insert(pause)
            summary.pausesInserted += 1
        }

        try repository.save()
        return summary
    }

    public static func merge(json data: Data, into repository: any HabitRepository) throws -> ImportSummary {
        try merge(BackupCoding.decode(data), into: repository)
    }

    // MARK: Applying a record over a live object

    private static func apply(_ record: BackupArchive.HabitRecord, to habit: Habit) {
        habit.name = record.name
        habit.emoji = record.emoji
        habit.colorHex = record.colorHex
        habit.rule = record.rule
        habit.schedule = record.schedule
        habit.progressModel = record.progressModel
        habit.adaptationMode = record.adaptationMode
        habit.sortOrder = record.sortOrder
        habit.createdAt = record.createdAt
        habit.archivedAt = record.archivedAt
        habit.lastGoalChangeAt = record.lastGoalChangeAt
        habit.lastProposalDismissedAt = record.lastProposalDismissedAt
        // Last, because the setters above stamp it with `Date()`.
        habit.updatedAt = record.updatedAt
    }

    private static func apply(_ record: BackupArchive.LogRecord, to log: DailyLog) {
        log.habitID = record.habitID
        log.dayKey = record.dayKey
        log.dayStart = record.dayStart
        log.timeZoneID = record.timeZoneID
        log.progressValue = record.progressValue
        log.targetValue = record.targetValue
        log.isCompleted = record.isCompleted
        log.completedAt = record.completedAt
        log.completionSource = record.completionSource
        log.notifiedAt = record.notifiedAt
        log.lastEvaluatedAt = record.lastEvaluatedAt
        log.updatedAt = record.updatedAt
    }
}
