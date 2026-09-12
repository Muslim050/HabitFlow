import EventKit
import Foundation
import Observation
import WidgetKit
import HabitCore

/// Reads today's calendar events and reminders. Read-mostly: the one write is ticking a
/// reminder off, which is what makes the strip worth having rather than decorative.
@MainActor
@Observable
final class CalendarService {
    private let store = EKEventStore()

    private(set) var items: [AgendaItem] = []
    private(set) var lastRefreshedAt: Date?
    private(set) var isRefreshing = false

    var eventsStatus: EKAuthorizationStatus { EKEventStore.authorizationStatus(for: .event) }
    var remindersStatus: EKAuthorizationStatus { EKEventStore.authorizationStatus(for: .reminder) }

    var hasAnyAccess: Bool {
        isGranted(eventsStatus) || isGranted(remindersStatus)
    }

    private func isGranted(_ status: EKAuthorizationStatus) -> Bool {
        status == .fullAccess || status == .authorized
    }

    // MARK: Access

    /// Asks for both; either one alone is enough to show something.
    @discardableResult
    func requestAccess() async -> Bool {
        // Two sequential prompts; iOS shows them one after the other anyway.
        let events = (try? await store.requestFullAccessToEvents()) ?? false
        let reminders = (try? await store.requestFullAccessToReminders()) ?? false
        let granted = events || reminders
        if granted { await refresh() }
        return granted
    }

    // MARK: Reading

    func refresh(now: Date = Date(), dayStart: Date? = nil, dayEnd: Date? = nil) async {
        guard hasAnyAccess else {
            items = []
            AgendaSnapshot.clear()
            WidgetCenter.shared.reloadAllTimelines()
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        let calendar = Calendar.current
        let start = dayStart ?? calendar.startOfDay(for: now)
        let end = dayEnd ?? (calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400))

        var collected: [AgendaItem] = []
        if isGranted(eventsStatus) {
            collected.append(contentsOf: events(from: start, to: end))
        }
        if isGranted(remindersStatus) {
            // Reach back a week so a reminder that slipped still shows as overdue.
            collected.append(contentsOf: await reminders(from: start.addingTimeInterval(-7 * 86_400), to: end))
        }
        items = collected
        lastRefreshedAt = now
        // The widget cannot read EventKit itself, so hand it what we just read.
        AgendaSnapshot.write(AgendaBuilder.arrange(collected, now: now, limit: 6), at: now)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func events(from start: Date, to end: Date) -> [AgendaItem] {
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).map { event in
            AgendaItem(
                id: event.eventIdentifier ?? UUID().uuidString,
                title: event.title ?? String(localized: "Untitled"),
                kind: .event,
                start: event.startDate,
                end: event.endDate,
                isAllDay: event.isAllDay,
                isCompleted: false,
                colorHex: Self.hex(from: event.calendar?.cgColor)
            )
        }
    }

    private func reminders(from start: Date, to end: Date) async -> [AgendaItem] {
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: start, ending: end, calendars: nil)
        let fetched: [EKReminder] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { continuation.resume(returning: $0 ?? []) }
        }
        return fetched.map { reminder in
            AgendaItem(
                id: reminder.calendarItemIdentifier,
                title: reminder.title ?? String(localized: "Untitled"),
                kind: .reminder,
                start: reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) },
                end: nil,
                isAllDay: false,
                isCompleted: reminder.isCompleted,
                colorHex: Self.hex(from: reminder.calendar?.cgColor)
            )
        }
    }

    // MARK: Writing

    /// Ticks a reminder off in the system Reminders app. Events are never modified.
    func complete(_ item: AgendaItem) async {
        guard item.kind == .reminder, isGranted(remindersStatus) else { return }
        guard let reminder = store.calendarItem(withIdentifier: item.id) as? EKReminder else { return }
        reminder.isCompleted = true
        do {
            try store.save(reminder, commit: true)
            items.removeAll { $0.id == item.id }
        } catch {
            Log.app.error("Could not complete reminder: \(error.localizedDescription)")
        }
    }

    private static func hex(from color: CGColor?) -> String? {
        guard let components = color?.components, components.count >= 3 else { return nil }
        let clamp = { (value: CGFloat) in Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", clamp(components[0]), clamp(components[1]), clamp(components[2]))
    }
}
