import Foundation
import SwiftData
import Testing
@testable import HabitCore

/// Personal history is irreplaceable, so the only test that really matters here is the round
/// trip: export, start from nothing, import, and get the same store back.
@Suite("Backup")
@MainActor
struct BackupTests {
    /// A store with one of everything worth losing.
    private func populated() throws -> (TestEnv, Habit, Habit) {
        let env = try TestEnv(now: Fixed.date(2026, 9, 19, 10, 0))
        let walk = try env.addHabit("Walk", rule: .healthQuantity(metric: .steps, target: 8000),
                                    schedule: .timesPerWeek(count: 3), createdDaysAgo: 40)
        walk.emoji = "🚶"
        walk.colorHex = "#FF8800"
        walk.progressModel = .completionRate
        walk.adaptationMode = .automatic

        let read = try env.addHabit("Read", rule: .manual, schedule: .weekdays(mask: 0b011_1110),
                                    createdDaysAgo: 20)
        read.archivedAt = Fixed.date(2026, 9, 18)

        for day in ["2026-09-08", "2026-09-10", "2026-09-13"] {
            try env.engine.setManualCompletion(habitID: walk.id, completed: true, dayKey: DayKey(raw: day))
        }
        let visit = GeofenceVisit(habitID: walk.id, enteredAt: Fixed.date(2026, 9, 12, 9, 0))
        visit.exitedAt = Fixed.date(2026, 9, 12, 10, 30)
        env.repository.insert(visit)
        env.repository.insert(HabitPause(habitID: nil, start: DayKey(raw: "2026-09-01"),
                                         end: DayKey(raw: "2026-09-03"), reason: .sick))
        env.repository.insert(HabitPause(habitID: walk.id, start: DayKey(raw: "2026-09-15"),
                                         end: nil, reason: .vacation))
        try env.repository.save()
        return (env, walk, read)
    }

    private func emptyStore() throws -> SwiftDataHabitRepository {
        SwiftDataHabitRepository(container: try ModelContainerFactory.inMemory())
    }

    // MARK: The round trip

    @Test func exportThenImportIntoAFreshStoreRestoresEverything() throws {
        let (env, _, _) = try populated()
        let data = try BackupExporter.json(from: env.repository)

        let restored = try emptyStore()
        let summary = try BackupImporter.merge(json: data, into: restored)
        #expect(summary.orphansSkipped == 0)

        // Comparing the files rather than the in-memory archives: the file is the promise, and
        // it is what a restore can actually be held to.
        let stamp = Fixed.date(2026, 1, 1)
        let reExported = try BackupExporter.json(from: restored, now: stamp)
        let original = try BackupExporter.json(from: env.repository, now: stamp)
        #expect(reExported == original, "a restored store must export the same file it was built from")
    }

    @Test func everyKindOfRecordSurvives() throws {
        let (env, walk, _) = try populated()
        let data = try BackupExporter.json(from: env.repository)
        let restored = try emptyStore()
        try BackupImporter.merge(json: data, into: restored)

        let habits = try restored.allHabits(includeArchived: true)
        #expect(habits.count == 2)
        let restoredWalk = try #require(habits.first { $0.id == walk.id })
        #expect(restoredWalk.name == "Walk")
        #expect(restoredWalk.emoji == "🚶")
        #expect(restoredWalk.colorHex == "#FF8800")
        #expect(restoredWalk.rule == .healthQuantity(metric: .steps, target: 8000))
        #expect(restoredWalk.schedule == .timesPerWeek(count: 3))
        #expect(restoredWalk.progressModel == .completionRate)
        #expect(restoredWalk.adaptationMode == .automatic)
        #expect(try restored.logs(habitID: walk.id, from: DayKey(raw: "2026-01-01"), to: DayKey(raw: "2026-12-31")).count == 3)
        #expect(try restored.allVisits().count == 1)
        #expect(try restored.pauses().count == 2)
        #expect(try restored.pauses().contains { $0.isGlobal && $0.reason == .sick })
        #expect(try restored.pauses().contains { $0.isRunning && $0.reason == .vacation })
    }

    @Test func anArchivedHabitStaysArchived() throws {
        let (env, _, read) = try populated()
        let data = try BackupExporter.json(from: env.repository)
        let restored = try emptyStore()
        try BackupImporter.merge(json: data, into: restored)

        let restoredRead = try #require(try restored.allHabits(includeArchived: true).first { $0.id == read.id })
        #expect(restoredRead.isArchived)
        #expect(try restored.activeHabits().count == 1)
    }

    // MARK: Merging into a store that is not empty

    @Test func importingTwiceChangesNothingTheSecondTime() throws {
        let (env, _, _) = try populated()
        let data = try BackupExporter.json(from: env.repository)
        let restored = try emptyStore()
        try BackupImporter.merge(json: data, into: restored)

        let second = try BackupImporter.merge(json: data, into: restored)
        #expect(second.isEmpty, "re-importing the same file is a no-op, not a duplication")
    }

    @Test func newerLocalWorkIsNotOverwritten() throws {
        let (env, walk, _) = try populated()
        let data = try BackupExporter.json(from: env.repository)

        // The habit was renamed after the export was taken.
        walk.name = "Walk further"
        walk.updatedAt = Fixed.date(2026, 9, 20)
        try env.repository.save()

        try BackupImporter.merge(json: data, into: env.repository)
        #expect(walk.name == "Walk further", "an older archive must not undo later work")
    }

    @Test func olderLocalRecordsAreBroughtForward() throws {
        let (env, walk, _) = try populated()
        walk.name = "Walk further"
        walk.updatedAt = Fixed.date(2026, 9, 20)
        try env.repository.save()
        let data = try BackupExporter.json(from: env.repository)

        // Roll the live copy back to something older than the archive.
        walk.name = "Walk"
        walk.updatedAt = Fixed.date(2026, 9, 1)
        try env.repository.save()

        let summary = try BackupImporter.merge(json: data, into: env.repository)
        #expect(walk.name == "Walk further")
        #expect(summary.habitsUpdated == 1)
    }

    @Test func aLogTheStoreAlreadyHasUnderAnotherIdIsMergedNotDuplicated() throws {
        let (env, walk, _) = try populated()
        let data = try BackupExporter.json(from: env.repository)

        let restored = try emptyStore()
        // The same day already exists, written independently, so its id differs.
        let clash = DailyLog(habitID: walk.id, dayKey: DayKey(raw: "2026-09-08"),
                             dayStart: Fixed.date(2026, 9, 8, 4, 0), targetValue: 8000)
        clash.updatedAt = Fixed.date(2026, 9, 8)
        // The habit has to exist first, or the log is an orphan.
        let carrier = Habit(name: "Walk", createdAt: Fixed.date(2026, 8, 1))
        carrier.id = walk.id
        restored.insert(carrier)
        restored.insert(clash)
        try restored.save()

        try BackupImporter.merge(json: data, into: restored)
        let logs = try restored.logs(habitID: walk.id, from: DayKey(raw: "2026-01-01"), to: DayKey(raw: "2026-12-31"))
        #expect(logs.count == 3, "one row per (habit, day), whatever ids the two sides used")
        #expect(logs.first { $0.dayKey == "2026-09-08" }?.isCompleted == true)
    }

    @Test func recordsNamingAMissingHabitAreSkipped() throws {
        let (env, _, _) = try populated()
        var archive = try BackupExporter.archive(from: env.repository)
        archive.habits = []

        let restored = try emptyStore()
        let summary = try BackupImporter.merge(archive, into: restored)
        #expect(summary.habitsInserted == 0)
        #expect(summary.logsInserted == 0)
        #expect(summary.orphansSkipped > 0, "a log without its habit is not something to guess at")
    }

    // MARK: The file itself

    @Test func anArchiveFromALaterBuildIsRefused() throws {
        let (env, _, _) = try populated()
        var archive = try BackupExporter.archive(from: env.repository)
        archive.version = BackupArchive.currentVersion + 1
        let data = try BackupCoding.encode(archive)

        #expect(throws: BackupError.tooNew(BackupArchive.currentVersion + 1)) {
            try BackupCoding.decode(data)
        }
    }

    @Test func rubbishIsReportedRatherThanPartlyApplied() throws {
        let restored = try emptyStore()
        #expect(throws: (any Error).self) {
            try BackupImporter.merge(json: Data("not json".utf8), into: restored)
        }
        #expect(try restored.allHabits(includeArchived: true).isEmpty)
    }

    @Test func csvHasAHeaderAndOneRowPerLog() throws {
        let (env, _, _) = try populated()
        let text = try #require(String(data: try BackupExporter.csv(from: env.repository), encoding: .utf8))
        let lines = text.split(separator: "\n")
        #expect(lines.first == "day,habit,emoji,value,target,completed,source,unit")
        #expect(lines.count == 4, "three logs plus the header")
        #expect(lines.contains { $0.hasPrefix("2026-09-08,Walk,🚶,") })
    }

    @Test func csvQuotesAFieldContainingAComma() throws {
        let env = try TestEnv()
        _ = try env.addHabit("Walk, then run", rule: .manual)
        let habit = try #require(try env.repository.activeHabits().first)
        try env.engine.setManualCompletion(habitID: habit.id, completed: true)

        let text = try #require(String(data: try BackupExporter.csv(from: env.repository), encoding: .utf8))
        #expect(text.contains("\"Walk, then run\""))
    }

    @Test func fileNameCarriesTheDay() {
        #expect(BackupExporter.fileName(for: DayKey(raw: "2026-09-19"), extension: "json")
                == "HabitFlow-2026-09-19.json")
    }
}
