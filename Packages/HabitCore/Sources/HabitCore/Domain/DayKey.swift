import Foundation

/// A logical day identifier in `yyyy-MM-dd` form. Comparable lexicographically.
public struct DayKey: Hashable, Comparable, Sendable, Codable, Identifiable, CustomStringConvertible {
    public let raw: String

    /// A day identifies itself; lets SwiftUI present a sheet straight from a selected day.
    public var id: String { raw }

    public init(raw: String) { self.raw = raw }

    public init(year: Int, month: Int, day: Int) {
        self.raw = String(format: "%04d-%02d-%02d", year, month, day)
    }

    public var components: (year: Int, month: Int, day: Int)? {
        let parts = raw.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return (parts[0], parts[1], parts[2])
    }

    public static func < (lhs: DayKey, rhs: DayKey) -> Bool { lhs.raw < rhs.raw }
    public var description: String { raw }
}
