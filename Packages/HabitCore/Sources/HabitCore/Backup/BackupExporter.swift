import Foundation

@MainActor
public enum BackupExporter {
    /// Everything in the store, ready to be written to a file.
    public static func archive(from repository: any HabitRepository, now: Date = Date()) throws -> BackupArchive {
        let habits = try repository.allHabits(includeArchived: true)
        return BackupArchive(
            exportedAt: now,
            habits: habits.map(record(of:)),
            logs: try repository.allLogs().map(record(of:)),
            visits: try repository.allVisits().map(record(of:)),
            pauses: try repository.pauses().map(record(of:))
        )
    }

    public static func json(from repository: any HabitRepository, now: Date = Date()) throws -> Data {
        try BackupCoding.encode(archive(from: repository, now: now))
    }

    /// One row per log, for a spreadsheet. Lossy on purpose — the JSON archive is what restores
    /// a store; this is for looking at the history somewhere else.
    public static func csv(from repository: any HabitRepository) throws -> Data {
        let habits = try repository.allHabits(includeArchived: true)
        let byID = Dictionary(habits.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var lines = ["day,habit,emoji,value,target,completed,source,unit"]
        for log in try repository.allLogs().sorted(by: { $0.dayKey < $1.dayKey }) {
            let habit = byID[log.habitID]
            lines.append([
                log.dayKey,
                field(habit?.name ?? ""),
                field(habit?.emoji ?? ""),
                number(log.progressValue),
                number(log.targetValue),
                log.isCompleted ? "true" : "false",
                log.completionSource.rawValue,
                field(habit?.rule.unitLabel ?? "")
            ].joined(separator: ","))
        }
        return Data(lines.joined(separator: "\n").utf8)
    }

    /// `2026-09-19` in the name so a folder of exports sorts itself.
    public static func fileName(for day: DayKey, extension ext: String) -> String {
        "HabitFlow-\(day.raw).\(ext)"
    }

    // MARK: Records

    private static func record(of habit: Habit) -> BackupArchive.HabitRecord {
        BackupArchive.HabitRecord(
            id: habit.id, name: habit.name, emoji: habit.emoji, colorHex: habit.colorHex,
            rule: habit.rule, schedule: habit.schedule, progressModel: habit.progressModel,
            adaptationMode: habit.adaptationMode, sortOrder: habit.sortOrder,
            createdAt: habit.createdAt, archivedAt: habit.archivedAt, updatedAt: habit.updatedAt,
            lastGoalChangeAt: habit.lastGoalChangeAt,
            lastProposalDismissedAt: habit.lastProposalDismissedAt
        )
    }

    private static func record(of log: DailyLog) -> BackupArchive.LogRecord {
        BackupArchive.LogRecord(
            id: log.id, habitID: log.habitID, dayKey: log.dayKey, dayStart: log.dayStart,
            timeZoneID: log.timeZoneID, progressValue: log.progressValue, targetValue: log.targetValue,
            isCompleted: log.isCompleted, completedAt: log.completedAt,
            completionSource: log.completionSource, notifiedAt: log.notifiedAt,
            lastEvaluatedAt: log.lastEvaluatedAt, updatedAt: log.updatedAt
        )
    }

    private static func record(of visit: GeofenceVisit) -> BackupArchive.VisitRecord {
        BackupArchive.VisitRecord(id: visit.id, habitID: visit.habitID, enteredAt: visit.enteredAt,
                                  exitedAt: visit.exitedAt, updatedAt: visit.updatedAt)
    }

    private static func record(of pause: HabitPause) -> BackupArchive.PauseRecord {
        BackupArchive.PauseRecord(id: pause.id, habitID: pause.habitID, startDayKey: pause.startDayKey,
                                  endDayKey: pause.endDayKey, reason: pause.reason,
                                  createdAt: pause.createdAt, updatedAt: pause.updatedAt)
    }

    // MARK: CSV escaping

    private static func field(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    /// A plain dot-decimal number: a CSV read by a machine must not depend on the writer's locale.
    private static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.4f", value)
    }
}
