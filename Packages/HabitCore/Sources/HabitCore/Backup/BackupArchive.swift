import Foundation

/// A whole store, written as plain values rather than as the SwiftData models.
///
/// The archive deliberately does not mirror the storage schema. Rules and schedules are stored
/// decoded, so the file stays readable and survives a change to how they are persisted, and
/// every record carries `updatedAt` so importing is a merge rather than a guess.
public struct BackupArchive: Codable, Sendable, Equatable {
    /// Bumped only when an older file can no longer be read as-is.
    public static let currentVersion = 1

    public var version: Int
    public var exportedAt: Date
    public var habits: [HabitRecord]
    public var logs: [LogRecord]
    public var visits: [VisitRecord]
    public var pauses: [PauseRecord]

    public init(version: Int = BackupArchive.currentVersion, exportedAt: Date,
                habits: [HabitRecord], logs: [LogRecord],
                visits: [VisitRecord] = [], pauses: [PauseRecord] = []) {
        self.version = version
        self.exportedAt = exportedAt
        self.habits = habits
        self.logs = logs
        self.visits = visits
        self.pauses = pauses
    }

    public struct HabitRecord: Codable, Sendable, Equatable {
        public var id: UUID
        public var name: String
        public var emoji: String
        public var colorHex: String
        public var rule: HabitRule
        public var schedule: HabitSchedule
        public var progressModel: ProgressModel
        public var adaptationMode: GoalAdaptationMode
        public var sortOrder: Int
        public var createdAt: Date
        public var archivedAt: Date?
        public var updatedAt: Date
        public var lastGoalChangeAt: Date?
        public var lastProposalDismissedAt: Date?
    }

    public struct LogRecord: Codable, Sendable, Equatable {
        public var id: UUID
        public var habitID: UUID
        public var dayKey: String
        public var dayStart: Date
        public var timeZoneID: String
        public var progressValue: Double
        public var targetValue: Double
        public var isCompleted: Bool
        public var completedAt: Date?
        public var completionSource: CompletionSource
        public var notifiedAt: Date?
        public var lastEvaluatedAt: Date?
        public var updatedAt: Date
    }

    public struct VisitRecord: Codable, Sendable, Equatable {
        public var id: UUID
        public var habitID: UUID
        public var enteredAt: Date
        public var exitedAt: Date?
        public var updatedAt: Date
    }

    public struct PauseRecord: Codable, Sendable, Equatable {
        public var id: UUID
        /// `nil` for a global pause.
        public var habitID: UUID?
        public var startDayKey: String
        /// Empty while the pause is still running.
        public var endDayKey: String
        public var reason: PauseReason
        public var createdAt: Date
        public var updatedAt: Date
    }
}

public enum BackupCoding {
    /// ISO 8601 with milliseconds. Plain `.iso8601` truncates to whole seconds, which would
    /// quietly round every timestamp in the file; readable dates are worth keeping, so this
    /// buys back the precision that actually matters without resorting to raw epoch numbers.
    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(dateFormatter.string(from: date))
        }
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = dateFormatter.date(from: text) else { throw BackupError.unreadable }
            return date
        }
        return decoder
    }

    public static func encode(_ archive: BackupArchive) throws -> Data {
        try encoder().encode(archive)
    }

    public static func decode(_ data: Data) throws -> BackupArchive {
        let archive = try decoder().decode(BackupArchive.self, from: data)
        guard archive.version <= BackupArchive.currentVersion else { throw BackupError.tooNew(archive.version) }
        return archive
    }
}

public enum BackupError: Error, Equatable, Sendable {
    /// Written by a later build than this one; refusing beats importing half of it.
    case tooNew(Int)
    case unreadable
}
