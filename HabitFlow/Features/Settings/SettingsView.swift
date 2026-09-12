import SwiftUI
import UIKit
import HabitCore

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @AppStorage(AppSettings.Key.dayStartHour, store: AppSettings.store) private var dayStartHour = 4
    @AppStorage(AppSettings.Key.nudgeEnabled, store: AppSettings.store) private var nudgeEnabled = true
    @AppStorage(AppSettings.Key.nudgeHour, store: AppSettings.store) private var nudgeHour = 20
    @AppStorage(AppSettings.Key.graceMissesPerWeek, store: AppSettings.store) private var grace = 1

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Day starts at", selection: $dayStartHour) {
                        ForEach(0...6, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
                    }
                    .onChange(of: dayStartHour) { _, _ in env.habitDidChange(nil) }
                } header: {
                    Text("Day boundary")
                } footer: {
                    Text("A late night still belongs to the previous day until this hour. Sleep is counted around it.")
                }

                Section {
                    Toggle("Evening reminder", isOn: $nudgeEnabled)
                    if nudgeEnabled {
                        Picker("Time", selection: $nudgeHour) {
                            ForEach(6...23, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
                        }
                    }
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("One notification per day listing only what is still open. Automatic completions notify on their own.")
                }

                Section {
                    Picker("New habits", selection: adaptationBinding) {
                        ForEach(GoalAdaptationMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                } header: {
                    Text("Adaptive goals")
                } footer: {
                    Text("Default for habits you create next. Each habit can be changed on its own.")
                }

                Section {
                    Stepper("Forgiven misses per week: \(grace)", value: $grace, in: 0...3)
                } header: {
                    Text("Streaks")
                } footer: {
                    Text("A streak survives this many misses in any 7 scheduled days.")
                }

                Section {
                    Toggle("Calendar and Reminders", isOn: agendaBinding)
                } header: {
                    Text("Also today")
                } footer: {
                    Text("Shows today's events and due reminders under your habits. Read-only, except ticking a reminder off.")
                }

                Section {
                    PermissionRow(title: "Health", status: healthStatusText) {
                        Task { try? await env.healthKit.requestAllReadAuthorization() }
                    }
                    PermissionRow(title: "Location", status: locationStatusText) {
                        if env.location.authorizationStatus == .notDetermined {
                            env.location.requestWhenInUseAuthorization()
                        } else {
                            env.location.requestAlwaysAuthorization()
                        }
                    }
                    Button("Open iOS Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                } header: {
                    Text("Permissions")
                } footer: {
                    Text("iOS does not reveal whether Health read access was granted. If a Health habit stays at 0, check Settings → Health → Data Access.")
                }

                Section {
                    Toggle("iCloud sync", isOn: .constant(false)).disabled(true)
                } footer: {
                    Text("Coming soon. Everything currently stays on this device.")
                }

                #if DEBUG
                Section("Developer") {
                    NavigationLink("Seed Health data") { DebugSeedView() }
                    NavigationLink("Pending notifications") { PendingNotificationsView() }
                    Button("Run auto-tracking now") {
                        Task { await env.engine.evaluateAll(reason: .manualRefresh) }
                    }
                    if let summary = env.lastSummary {
                        Text("Last run: \(summary.evaluatedHabitIDs.count) evaluated, \(summary.completions.count) completed, \(summary.failures.count) failed")
                            .font(.footnote).foregroundStyle(.secondary)
                        ForEach(Array(summary.failures.keys), id: \.self) { id in
                            Text(summary.failures[id] ?? "").font(.caption).foregroundStyle(.red)
                        }
                    }
                }
                #endif
            }
            .navigationTitle("Settings")
        }
    }

    private var adaptationBinding: Binding<GoalAdaptationMode> {
        Binding(
            get: { env.settings.defaultAdaptationMode },
            set: { env.settings.defaultAdaptationMode = $0 }
        )
    }

    private var agendaBinding: Binding<Bool> {
        Binding(
            get: { env.settings.agendaEnabled },
            set: { newValue in
                env.settings.agendaEnabled = newValue
                if newValue {
                    Task {
                        await env.calendar.requestAccess()
                        await env.calendar.refresh()
                    }
                }
            }
        )
    }

    private var healthStatusText: String {
        guard env.healthKit.isAvailable else { return String(localized: "Unavailable") }
        return env.settings.healthAuthorizationRequested ? String(localized: "Requested") : String(localized: "Not requested")
    }

    private var locationStatusText: String {
        switch env.location.authorizationStatus {
        case .notDetermined: return String(localized: "Not requested")
        case .authorizedWhenInUse: return String(localized: "While using (tap for Always)")
        case .authorizedAlways: return String(localized: "Always")
        case .denied, .restricted: return String(localized: "Denied")
        @unknown default: return String(localized: "Unknown")
        }
    }
}

struct PermissionRow: View {
    let title: LocalizedStringKey
    let status: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                Text(status).foregroundStyle(.secondary)
            }
        }
    }
}

struct PendingNotificationsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var requests: [String] = []

    var body: some View {
        List(requests, id: \.self) { Text($0).font(.footnote) }
            .overlay { if requests.isEmpty { ContentUnavailableView("Nothing pending", systemImage: "bell.slash") } }
            .navigationTitle("Pending")
            .task {
                requests = await env.notifications.pendingRequests().map { "\($0.identifier): \($0.content.title) — \($0.content.body)" }
            }
    }
}
