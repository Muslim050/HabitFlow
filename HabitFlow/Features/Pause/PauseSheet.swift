import SwiftData
import SwiftUI
import HabitCore

/// Starts a pause for one habit, or for everything at once when `habit` is nil.
/// The wording never calls a paused day a miss, because it is not one: a paused day asks
/// for nothing, so there is nothing to have failed.
struct PauseSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    /// `nil` pauses every habit.
    let habit: Habit?

    @State private var reason: PauseReason = .vacation
    @State private var hasEnd = true
    @State private var end = Date().addingTimeInterval(7 * 86_400)

    private var dayCalendar: DayCalendar { env.settings.dayCalendar }

    var body: some View {
        NavigationStack {
            Form {
                Section("Reason") {
                    Picker("Reason", selection: $reason) {
                        ForEach(PauseReason.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Toggle("Set an end date", isOn: $hasEnd)
                    if hasEnd {
                        DatePicker("Until", selection: $end, in: Date()..., displayedComponents: .date)
                    }
                } footer: {
                    Text(hasEnd
                         ? "Nothing is asked of these days and nothing is counted against them."
                         : "Runs until you resume it. Nothing is asked of these days and nothing is counted against them.")
                }
            }
            .navigationTitle(habit.map { Text($0.name) } ?? Text("Pause everything"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Pause") { start() } }
            }
        }
    }

    private func start() {
        let today = env.currentDayKey
        // The picker speaks in civil dates; convert by components so a day start above midnight
        // does not shift the last paused day back by one.
        let parts = dayCalendar.calendar.dateComponents([.year, .month, .day], from: end)
        let endKey = hasEnd ? DayKey(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0) : nil
        let pause = HabitPause(habitID: habit?.id, start: today,
                               end: endKey.map { max($0, today) }, reason: reason)
        env.repository.insert(pause)
        try? env.repository.save()
        env.pausesDidChange()
        dismiss()
    }
}

extension PauseReason {
    var displayName: String {
        switch self {
        case .vacation: return String(localized: "Holiday")
        case .sick: return String(localized: "Unwell")
        case .other: return String(localized: "Break")
        }
    }

    var systemImage: String {
        switch self {
        case .vacation: return "beach.umbrella"
        case .sick: return "cross.case"
        case .other: return "pause.circle"
        }
    }
}

/// One row describing a running pause, with the way out of it.
struct PauseRow: View {
    @Environment(AppEnvironment.self) private var env
    let pause: HabitPause

    var body: some View {
        HStack {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(pause.reason.displayName)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: pause.reason.systemImage)
            }
            Spacer()
            Button("Resume") { resume() }
                .buttonStyle(.borderless)
        }
    }

    private var subtitle: String {
        guard let end = pause.span.end else { return String(localized: "Until you resume it") }
        return String(localized: "Until \(end.formatted(calendar: env.settings.dayCalendar))")
    }

    private func resume() {
        // Ending yesterday rather than today: today should be askable again straight away.
        let yesterday = env.settings.dayCalendar.key(byAdding: -1, to: env.currentDayKey)
        if pause.span.start > yesterday {
            env.repository.delete(pause)   // never actually took effect
        } else {
            pause.end(on: yesterday)
        }
        try? env.repository.save()
        env.pausesDidChange()
    }
}
