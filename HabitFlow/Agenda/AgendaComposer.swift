import SwiftUI
import HabitCore

/// Creates an event or a reminder in the system stores. Deliberately small: Calendar and
/// Reminders do the full job better, this is for the thing you thought of while looking
/// at your habits.
struct AgendaComposer: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var draft: AgendaDraft
    @State private var isSaving = false
    @State private var failed = false
    /// Set when the draft came from a habit, to explain where the time came from.
    private let origin: String?

    init(draft: AgendaDraft = AgendaDraft(date: AgendaDraft.nextQuarterHour()), origin: String? = nil) {
        _draft = State(initialValue: draft)
        self.origin = origin
    }

    private var service: CalendarService { env.calendar }
    private var containers: [CalendarService.Container] { service.containers(for: draft.kind) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Kind", selection: $draft.kind) {
                        Text("Event").tag(AgendaItem.Kind.event)
                        Text("Reminder").tag(AgendaItem.Kind.reminder)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: draft.kind) { _, _ in draft.containerID = nil }

                    TextField("Title", text: $draft.title)
                }

                Section {
                    if draft.kind == .reminder {
                        Toggle("Set a time", isOn: $draft.hasTime)
                    }
                    DatePicker(draft.kind == .event ? "Starts" : "Due",
                               selection: $draft.date,
                               displayedComponents: draft.hasTime ? [.date, .hourAndMinute] : [.date])

                    if draft.kind == .event {
                        Picker("Duration", selection: $draft.durationMinutes) {
                            ForEach(AgendaDraft.durations, id: \.self) { minutes in
                                Text("\(minutes) min").tag(minutes)
                            }
                        }
                    }

                    Picker("Repeat", selection: $draft.repeats) {
                        ForEach(AgendaDraft.Repeat.allCases) { Text($0.title).tag($0) }
                    }
                } footer: {
                    if let origin {
                        Text(origin)
                    }
                }

                if !containers.isEmpty {
                    Section {
                        Picker(draft.kind == .event ? "Calendar" : "List", selection: containerBinding) {
                            Text("Default").tag(String?.none)
                            ForEach(containers) { container in
                                Text(container.title).tag(String?.some(container.id))
                            }
                        }
                    } footer: {
                        // Two whole sentences: interpolating the app's name left it untranslated.
                        Text(draft.kind == .event
                             ? "Saved straight into the system Calendar, so it syncs everywhere you are signed in."
                             : "Saved straight into the system Reminders, so it syncs everywhere you are signed in.")
                    }
                }

                if failed {
                    Text("Could not save. Check access in iOS Settings.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle(draft.kind == .event ? "New event" : "New reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .disabled(!draft.isValid || isSaving)
                }
            }
            .task {
                if draft.containerID == nil {
                    draft.containerID = service.defaultContainerID(for: draft.kind)
                }
            }
        }
    }

    private var containerBinding: Binding<String?> {
        Binding(get: { draft.containerID }, set: { draft.containerID = $0 })
    }

    private func save() {
        isSaving = true
        Task {
            let ok = await service.create(draft)
            isSaving = false
            if ok { dismiss() } else { failed = true }
        }
    }
}

extension AgendaDraft.Repeat {
    var title: LocalizedStringKey {
        switch self {
        case .never: return "Never"
        case .daily: return "Every day"
        case .weekdays: return "Weekdays"
        case .weekly: return "Every week"
        }
    }
}
