import EventKit
import SwiftUI
import HabitCore

/// What else is on today, under the habits: events from Calendar and reminders that are due.
/// Habits are what the app measures; this is the context around them.
struct AgendaSection: View {
    @Environment(AppEnvironment.self) private var env
    @AppStorage(AppSettings.Key.agendaEnabled, store: AppSettings.store) private var enabled = false

    private var service: CalendarService { env.calendar }

    private var visible: [AgendaItem] { AgendaBuilder.arrange(service.items, now: Date()) }
    private var overflow: Int { AgendaBuilder.overflow(service.items, now: Date()) }

    var body: some View {
        if enabled {
            if service.hasAnyAccess {
                if visible.isEmpty {
                    Text("Nothing else scheduled today.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(visible) { row($0) }
                    if overflow > 0 {
                        Text("+\(overflow) more").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                grantRow
            }
        }
    }

    private func row(_ item: AgendaItem) -> some View {
        HStack(spacing: 12) {
            Capsule()
                .fill(item.colorHex.map { Color(hex: $0) } ?? Color.accentColor)
                .frame(width: 3, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.body).lineLimit(1)
                Text(subtitle(item))
                    .font(.caption)
                    .foregroundStyle(item.isOverdue(now: Date()) ? Color.red : Color.secondary)
            }
            Spacer(minLength: 8)

            if item.kind == .reminder {
                Button {
                    Task { await service.complete(item) }
                } label: {
                    Image(systemName: "circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Complete \(item.title)"))
            } else {
                Image(systemName: "calendar")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func subtitle(_ item: AgendaItem) -> String {
        if item.isAllDay { return String(localized: "All day") }
        guard let start = item.start else { return String(localized: "No date") }
        let time = start.formatted(date: .omitted, time: .shortened)
        if item.isOverdue(now: Date()) { return String(localized: "Overdue · \(time)") }
        return time
    }

    private var grantRow: some View {
        Button {
            Task { await service.requestAccess() }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Connect Calendar and Reminders").font(.body)
                Text("Read-only, except ticking a reminder off. Nothing is copied into HabitFlow.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
