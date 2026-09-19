import Foundation

public enum PauseReason: String, Codable, CaseIterable, Sendable, Hashable {
    case vacation, sick, other
}

/// A stretch of days a habit is not asked for. Paused days create no obligation at all, which
/// is what "frozen, not missed" has to mean: nothing to keep, so nothing to lose.
public struct PauseSpan: Sendable, Equatable, Hashable, Codable {
    public var start: DayKey
    /// Inclusive. `nil` while the pause is still running.
    public var end: DayKey?
    public var reason: PauseReason

    public init(start: DayKey, end: DayKey? = nil, reason: PauseReason = .other) {
        self.start = start
        self.end = end
        self.reason = reason
    }

    public func contains(_ key: DayKey) -> Bool {
        guard key >= start else { return false }
        guard let end else { return true }
        return key <= end
    }

    public var isRunning: Bool { end == nil }
}

public extension Collection where Element == PauseSpan {
    func covers(_ key: DayKey) -> Bool { contains { $0.contains(key) } }

    /// The pause in force on that day, for wording that names the reason.
    func span(on key: DayKey) -> PauseSpan? { first { $0.contains(key) } }
}
