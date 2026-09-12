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

    // MARK: Containers

    struct Container: Identifiable, Hashable {
        let id: String
        let title: String
        let colorHex: String?
    }

    /// Calendars that accept new events, or lists that accept new reminders.
    func containers(for kind: AgendaItem.Kind) -> [Container] {
        let entity: EKEntityType = kind == .event ? .event : .reminder
        guard isGranted(entity == .event ? eventsStatus : remindersStatus) else { return [] }
        return store.calendars(for: entity)
            .filter(\.allowsContentModifications)
            .map { Container(id: $0.calendarIdentifier, title: $0.title, colorHex: Self.hex(from: $0.cgColor)) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func defaultContainerID(for kind: AgendaItem.Kind) -> String? {
        kind == .event
            ? store.defaultCalendarForNewEvents?.calendarIdentifier
            : store.defaultCalendarForNewReminders()?.calendarIdentifier
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

    /// Creates the draft in the system store, so it shows up in Calendar or Reminders
    /// on every device the person signs into, not only here.
    @discardableResult
    func create(_ draft: AgendaDraft) async -> Bool {
        guard draft.isValid else { return false }
        let entity: EKEntityType = draft.kind == .event ? .event : .reminder
        guard isGranted(entity == .event ? eventsStatus : remindersStatus) else { return false }

        let container = draft.containerID.flatMap { store.calendar(withIdentifier: $0) }
        do {
            switch draft.kind {
            case .event:
                let event = EKEvent(eventStore: store)
                event.title = draft.trimmedTitle
                event.startDate = draft.date
                event.endDate = draft.endDate
                event.calendar = container ?? store.defaultCalendarForNewEvents
                if let rule = Self.recurrence(for: draft) { event.recurrenceRules = [rule] }
                try store.save(event, span: .futureEvents, commit: true)

            case .reminder:
                let reminder = EKReminder(eventStore: store)
                reminder.title = draft.trimmedTitle
                reminder.calendar = container ?? store.defaultCalendarForNewReminders()
                let fields: Set<Calendar.Component> = draft.hasTime
                    ? [.year, .month, .day, .hour, .minute]
                    : [.year, .month, .day]
                reminder.dueDateComponents = Calendar.current.dateComponents(fields, from: draft.date)
                if let rule = Self.recurrence(for: draft) { reminder.recurrenceRules = [rule] }
                try store.save(reminder, commit: true)
            }
        } catch {
            Log.app.error("Could not create \(draft.kind.rawValue): \(error.localizedDescription)")
            return false
        }
        await refresh()
        return true
    }

    private static func recurrence(for draft: AgendaDraft) -> EKRecurrenceRule? {
        switch draft.repeats {
        case .never:
            return nil
        case .daily:
            return EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil)
        case .weekdays, .weekly:
            let days = (draft.weekdays() ?? []).compactMap { EKWeekday(rawValue: $0) }
                .map { EKRecurrenceDayOfWeek($0) }
            guard !days.isEmpty else { return nil }
            return EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, daysOfTheWeek: days,
                                    daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil,
                                    daysOfTheYear: nil, setPositions: nil, end: nil)
        }
    }

    private static func hex(from color: CGColor?) -> String? {
        guard let components = color?.components, components.count >= 3 else { return nil }
        let clamp = { (value: CGFloat) in Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", clamp(components[0]), clamp(components[1]), clamp(components[2]))
    }
}
