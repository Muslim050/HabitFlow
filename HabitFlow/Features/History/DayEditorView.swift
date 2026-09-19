import SwiftData
import SwiftUI
import HabitCore

/// Fixes a day that has already passed — the Health sample that never arrived, the walk the phone
/// slept through. Reachable by tapping a heat-map cell, but carries its own date picker so the
/// feature does not depend on hitting a 13-point square.
struct DayEditorView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Query private var pauses: [HabitPause]

    let habit: Habit
    @State private var date: Date
    @State private var valueText: String = ""
    @State private var failure: String?

    init(habit: Habit, dayKey: DayKey, calendar: DayCalendar) {
        self.habit = habit
        _date = State(initialValue: Self.civilDate(of: dayKey, in: calendar))
    }

    private var dayCalendar: DayCalendar { env.settings.dayCalendar }

    /// The picker speaks in civil dates; the store speaks in logical days. Convert by calendar
    /// components, never through `dayKey(for:)` — midnight maps to the *previous* logical day
    /// whenever `dayStartHour` is above zero.
    private var dayKey: DayKey {
        let parts = dayCalendar.calendar.dateComponents([.year, .month, .day], from: date)
        return DayKey(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0)
    }

    private static func civilDate(of key: DayKey, in calendar: DayCalendar) -> Date {
        guard let parts = key.components else { return Date() }
        var comps = DateComponents()
        comps.year = parts.year; comps.month = parts.month; comps.day = parts.day
        comps.hour = 12  // noon keeps the date stable across DST shifts
        return calendar.calendar.date(from: comps) ?? Date()
    }

    private var range: ClosedRange<Date> {
        let editable = env.engine.editableDayRange()
        let earliest = max(editable.lowerBound, dayCalendar.dayKey(for: habit.createdAt))
        let latest = max(earliest, editable.upperBound)  // a ClosedRange traps if it runs backwards
        return Self.civilDate(of: earliest, in: dayCalendar)...Self.civilDate(of: latest, in: dayCalendar)
    }

    private var log: DailyLog? {
        _ = env.evaluationTick
        return try? env.repository.log(habitID: habit.id, dayKey: dayKey)
    }

    private var isCompleted: Bool { log?.isCompleted ?? false }
    private var obligation: DayObligation {
        habit.obligation(on: dayKey, calendar: dayCalendar, pauses: pauses.spans(for: habit.id))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Day", selection: $date, in: range, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                }

                Section("State") {
                    LabeledContent("Status") {
                        Text(statusText).foregroundStyle(isCompleted ? Color(hex: habit.colorHex) : .secondary)
                    }
                    if let note = scheduleNote {
                        Text(note).font(.caption).foregroundStyle(.secondary)
                    }
                }

                if habit.isAutomatic {
                    Section("Measured value") {
                        HStack {
                            TextField("Value", text: $valueText)
                                .keyboardType(.decimalPad)
                                .font(.body.monospacedDigit())
                            Text(habit.rule.localizedUnit).foregroundStyle(.secondary)
                        }
                        Button("Save value") { saveValue() }
                            .disabled(Double(valueText.replacingOccurrences(of: ",", with: ".")) == nil)
                        Text("Compared against the goal in force that day, not today's goal.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button {
                        apply { try env.engine.setManualCompletion(habitID: habit.id, completed: !isCompleted, dayKey: dayKey) }
                    } label: {
                        Label(isCompleted ? "Mark not done" : "Mark done",
                              systemImage: isCompleted ? "xmark.circle" : "checkmark.circle")
                    }
                    if log?.completionSource == .manualOverride {
                        Button {
                            let key = dayKey
                            Task { try? await env.engine.clearOverride(habitID: habit.id, dayKey: key) }
                        } label: { Label("Let auto-tracking decide", systemImage: "arrow.clockwise") }
                    }
                }

                if let failure {
                    Section { Text(failure).font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle(habit.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onChange(of: date) { _, _ in syncValueField() }
            .onAppear { syncValueField() }
        }
    }

    /// Why this day looks the way it does, when the schedule makes it non-obvious.
    private var scheduleNote: LocalizedStringKey? {
        switch obligation {
        case .required: return nil
        case .flexible: return "Any day of the period counts towards the goal."
        case .paused: return "The habit was paused that day. Marking it still counts."
        case .off: return "This day is not in the habit's schedule. Marking it still counts."
        }
    }

    private var statusText: String {
        guard let log else { return String(localized: "No record") }
        if habit.isAutomatic {
            return ValueFormatting.progress(value: log.progressValue, target: log.targetValue, unit: habit.rule.unitLabel)
        }
        // "Completed", not "Done": the latter is the sheet's dismiss button and reads wrong as a state.
        return log.isCompleted ? String(localized: "Completed") : String(localized: "Not done")
    }

    private func syncValueField() {
        failure = nil
        guard habit.isAutomatic else { return }
        let current = log?.progressValue ?? 0
        valueText = current > 0 ? String(format: "%g", current) : ""
    }

    private func saveValue() {
        guard let value = Double(valueText.replacingOccurrences(of: ",", with: ".")) else { return }
        apply { try env.engine.setManualValue(habitID: habit.id, value: value, dayKey: dayKey) }
    }

    private func apply(_ work: () throws -> Void) {
        do {
            try work()
            failure = nil
        } catch BackdateError.dayNotEditable {
            failure = String(localized: "That day is outside the editable range.")
        } catch {
            failure = error.localizedDescription
        }
    }
}
