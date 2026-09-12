import Foundation

/// One thing from the system Calendar or Reminders, flattened to what the day strip needs.
/// Read from EventKit in the app; kept here so the ordering rules can be tested on their own.
public struct AgendaItem: Identifiable, Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Equatable, Codable {
        case event, reminder
    }

    public var id: String
    public var title: String
    public var kind: Kind
    /// Event start, or a reminder's due date. `nil` for a reminder with no date.
    public var start: Date?
    public var end: Date?
    public var isAllDay: Bool
    public var isCompleted: Bool
    /// The calendar's or list's own colour, so the strip keeps the user's colour coding.
    public var colorHex: String?

    public init(id: String, title: String, kind: Kind, start: Date? = nil, end: Date? = nil,
                isAllDay: Bool = false, isCompleted: Bool = false, colorHex: String? = nil) {
        self.id = id
        self.title = title
        self.kind = kind
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.isCompleted = isCompleted
        self.colorHex = colorHex
    }

    /// A reminder whose due time has passed. Events are never overdue: they simply happened.
    public func isOverdue(now: Date) -> Bool {
        guard kind == .reminder, !isCompleted, let start else { return false }
        return start < now
    }

    /// A timed event that has already finished.
    public func hasFinished(now: Date) -> Bool {
        guard kind == .event, !isAllDay else { return false }
        guard let end else { return false }
        return end <= now
    }
}

public enum AgendaBuilder {
    /// What is still ahead today, most actionable first: overdue reminders, then all-day
    /// entries, then the rest of the day in order, then reminders with no time on them.
    /// Completed reminders and events that already ended drop out — the strip is about
    /// what is left, not a log of the day.
    public static func arrange(_ items: [AgendaItem], now: Date, limit: Int = 5) -> [AgendaItem] {
        guard limit > 0 else { return [] }
        let live = items.filter { !$0.isCompleted && !$0.hasFinished(now: now) }

        func rank(_ item: AgendaItem) -> Int {
            if item.isOverdue(now: now) { return 0 }
            if item.isAllDay { return 1 }
            if item.start != nil { return 2 }
            return 3
        }

        let sorted = live.sorted { lhs, rhs in
            let (l, r) = (rank(lhs), rank(rhs))
            if l != r { return l < r }
            switch (lhs.start, rhs.start) {
            case let (a?, b?) where a != b: return a < b
            default: return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }
        return Array(sorted.prefix(limit))
    }

    /// How many live items did not fit, so the strip can say "+3 more" honestly.
    public static func overflow(_ items: [AgendaItem], now: Date, limit: Int = 5) -> Int {
        let live = items.filter { !$0.isCompleted && !$0.hasFinished(now: now) }
        return max(0, live.count - limit)
    }
}

/// The app reads EventKit and leaves a small snapshot in the App Group; the widget reads
/// that. A widget extension cannot ask for calendar permission, so it must not try to.
public enum AgendaSnapshot {
    public static let key = "agendaSnapshot"

    private struct Payload: Codable {
        var items: [AgendaItem]
        var writtenAt: Date
    }

    public static func write(_ items: [AgendaItem], at date: Date = Date(),
                             defaults: UserDefaults = AppSettings.store) {
        // Keep it small: the strip shows a handful, and UserDefaults is not a database.
        let payload = Payload(items: Array(items.prefix(12)), writtenAt: date)
        defaults.set(try? JSONEncoder().encode(payload), forKey: key)
    }

    public static func read(defaults: UserDefaults = AppSettings.store) -> (items: [AgendaItem], writtenAt: Date)? {
        guard let data = defaults.data(forKey: key),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        return (payload.items, payload.writtenAt)
    }

    public static func clear(defaults: UserDefaults = AppSettings.store) {
        defaults.removeObject(forKey: key)
    }
}
