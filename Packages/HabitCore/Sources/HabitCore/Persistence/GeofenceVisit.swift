import Foundation
import SwiftData

/// One stay inside a habit's geofence. `exitedAt == nil` means the user is still there.
@Model
public final class GeofenceVisit {
    public var id: UUID = UUID()
    public var habitID: UUID = UUID()
    public var enteredAt: Date = Date()
    public var exitedAt: Date? = nil
    public var updatedAt: Date = Date()

    public init(habitID: UUID, enteredAt: Date) {
        self.id = UUID()
        self.habitID = habitID
        self.enteredAt = enteredAt
        self.updatedAt = enteredAt
    }

    public var isOpen: Bool { exitedAt == nil }

    /// Interval of the stay, using `now` as the end for open visits.
    public func interval(now: Date) -> DateInterval {
        let end = max(exitedAt ?? now, enteredAt)
        return DateInterval(start: enteredAt, end: end)
    }
}
