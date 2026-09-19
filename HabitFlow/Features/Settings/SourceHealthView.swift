import SwiftData
import SwiftUI
import HabitCore

/// Why a habit did not close itself.
///
/// Five different failures look identical from the Today screen — an empty ring: Health has no
/// data, read permission was never granted (iOS refuses to say), background delivery stopped, the
/// region was never registered, the refresh task has not been given time for days. None of it can
/// be observed on the Simulator, so on a real phone this screen is the only way to tell them apart.
struct SourceHealthView: View {
    @Environment(AppEnvironment.self) private var env
    @Query(sort: [SortDescriptor(\Habit.sortOrder)]) private var allHabits: [Habit]
    @State private var tick = 0

    private var automatic: [Habit] { allHabits.filter { $0.archivedAt == nil && $0.isAutomatic } }
    private var geofenceHabits: [Habit] { automatic.filter { $0.kind == .geofence } }

    var body: some View {
        List {
            Section {
                Row(title: "Last check", value: relative(env.settings.lastEngineRunAt))
                if let summary = env.lastSummary {
                    Row(title: "Habits looked at", value: "\(summary.evaluatedHabitIDs.count)")
                    if !summary.failures.isEmpty {
                        Row(title: "Failed", value: "\(summary.failures.count)", tone: .red)
                    }
                }
                Button("Check now") {
                    Task {
                        await env.engine.evaluateAll(reason: .manualRefresh)
                        tick += 1
                    }
                }
            } header: {
                Text("Engine")
            } footer: {
                Text("Runs when the app is open, when Health or a place reports something, and on a background refresh.")
            }

            Section {
                Row(title: "Last background refresh", value: relative(SourceHealth.lastBackgroundRefreshAt),
                    tone: SourceHealth.lastBackgroundRefreshAt == nil ? .warning : .normal)
                if let outcome = SourceHealth.lastBackgroundRefreshOutcome {
                    Row(title: "Result", value: outcome)
                }
            } header: {
                Text("Background refresh")
            } footer: {
                Text("iOS decides when to grant this, and never does in the Simulator. Empty after a few days on a real phone means it is not being scheduled.")
            }

            healthSection
            if !geofenceHabits.isEmpty { placesSection }
            habitsSection
        }
        .navigationTitle("Sources")
        .navigationBarTitleDisplayMode(.inline)
        .id(tick)
    }

    // MARK: Health

    @ViewBuilder
    private var healthSection: some View {
        let kinds: [HabitSourceKind] = [.healthQuantity, .healthSleep, .healthMindful, .healthWorkout]
        let used = kinds.filter { kind in automatic.contains { $0.kind == kind } }
        Section {
            // Plain literals here would ship untranslated: these are values, not view titles.
            Row(title: "Available on this device",
                value: env.healthKit.isAvailable ? String(localized: "Yes") : String(localized: "No"),
                tone: env.healthKit.isAvailable ? .normal : .red)
            Row(title: "Permission asked",
                value: env.settings.healthAuthorizationRequested ? String(localized: "Yes") : String(localized: "Not yet"),
                tone: env.settings.healthAuthorizationRequested ? .normal : .warning)
            if used.isEmpty {
                Text("No habits read from Health.").font(.footnote).foregroundStyle(.secondary)
            } else {
                ForEach(used, id: \.self) { kind in
                    let report = SourceHealth.report(for: kind)
                    Row(verbatim: kind.displayName, value: relative(report.lastDeliveryAt),
                        tone: report.hasEverDelivered ? .normal : .warning)
                }
            }
        } header: {
            Text("Health")
        } footer: {
            Text("The time each kind last pushed a change at the app. iOS never reveals whether read access was granted, so a source that has delivered nothing at all is the sign to check Settings → Health → Data Access.")
        }
    }

    // MARK: Places

    @ViewBuilder
    private var placesSection: some View {
        let registered = env.location.monitoredRegionCount
        let wanted = geofenceHabits.count
        let report = SourceHealth.report(for: .geofence)
        Section {
            Row(title: "Permission", value: authorizationText,
                tone: env.location.hasAlwaysAuthorization ? .normal : .warning)
            Row(title: "Places being watched", value: "\(registered) of \(wanted)",
                tone: registered < wanted ? .warning : .normal)
            Row(title: "Last arrival or departure", value: relative(report.lastDeliveryAt),
                tone: report.hasEverDelivered ? .normal : .warning)
        } header: {
            Text("Places")
        } footer: {
            Text("Marking a place-based habit while the app is closed needs Always. Fewer places watched than habits means some region did not register — iOS allows 20 at once.")
        }
    }

    private var authorizationText: String {
        if env.location.hasAlwaysAuthorization { return String(localized: "Always") }
        if env.location.hasAnyAuthorization { return String(localized: "While using the app") }
        return String(localized: "Not granted")
    }

    // MARK: Per habit

    @ViewBuilder
    private var habitsSection: some View {
        if !automatic.isEmpty {
            Section {
                ForEach(automatic) { habit in
                    let report = SourceHealth.report(for: habit.kind)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(habit.emoji) \(habit.name)")
                        Text(reading(for: habit, report: report))
                            .font(.caption)
                            .foregroundStyle(report.lastError == nil ? .secondary : Color.red)
                    }
                }
            } header: {
                Text("What each habit last read")
            } footer: {
                Text("A value of zero means the source answered and had nothing. No reading at all means it was never asked or never answered — a different problem.")
            }
        }
    }

    private func reading(for habit: Habit, report: SourceReport) -> String {
        if let error = report.lastError { return error }
        guard let read = report.lastReadAt, let value = report.lastValue else {
            return String(localized: "Never read")
        }
        let amount = ValueFormatting.progressless(target: value, unit: habit.rule.unitLabel)
        return "\(amount) · \(relative(read))"
    }

    // MARK: Bits

    private func relative(_ date: Date?) -> String {
        guard let date else { return String(localized: "Never") }
        return date.formatted(.relative(presentation: .named))
    }

    private enum Tone { case normal, warning, red }

    private struct Row: View {
        let title: Text
        let value: String
        var tone: Tone = .normal

        init(title: LocalizedStringKey, value: String, tone: Tone = .normal) {
            self.title = Text(title)
            self.value = value
            self.tone = tone
        }

        /// For names that are already localized at runtime, such as a source kind.
        init(verbatim title: String, value: String, tone: Tone = .normal) {
            self.title = Text(title)
            self.value = value
            self.tone = tone
        }

        var body: some View {
            HStack {
                title
                Spacer()
                Text(value)
                    .foregroundStyle(colour)
                    .multilineTextAlignment(.trailing)
            }
        }

        private var colour: Color {
            switch tone {
            case .normal: return .secondary
            case .warning: return .orange
            case .red: return .red
            }
        }
    }
}
