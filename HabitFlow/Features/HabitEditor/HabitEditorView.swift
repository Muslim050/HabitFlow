import CoreLocation
import SwiftUI
import HabitCore

struct HabitEditorView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    private let existing: Habit?

    @State private var name: String
    @State private var emoji: String
    @State private var colorHex: String
    @State private var kind: HabitSourceKind
    @State private var metric: HealthMetric
    @State private var quantityTarget: Double
    @State private var sleepHours: Double
    @State private var mindfulMinutes: Double
    @State private var workoutMinutes: Double
    @State private var workoutActivity: WorkoutActivity
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var radius: Double
    @State private var dwellMinutes: Double
    @State private var placeName: String
    @State private var schedule: HabitSchedule
    @State private var progressModel: ProgressModel
    @State private var adaptationMode: GoalAdaptationMode
    @State private var showPlacePicker = false

    init(habit: Habit?) {
        existing = habit
        let rule = habit?.rule ?? .manual
        _name = State(initialValue: habit?.name ?? "")
        _emoji = State(initialValue: habit?.emoji ?? "✅")
        _colorHex = State(initialValue: habit?.colorHex ?? HabitPalette.hexes[0])
        _kind = State(initialValue: rule.kind)
        _schedule = State(initialValue: habit?.schedule ?? .everyDay)
        _progressModel = State(initialValue: habit?.progressModel ?? AppSettings.shared.defaultProgressModel)
        _adaptationMode = State(initialValue: habit?.adaptationMode ?? AppSettings.shared.defaultAdaptationMode)

        var metric = HealthMetric.steps
        var quantityTarget = HealthMetric.steps.defaultTarget
        var sleepHours = 7.5
        var mindfulMinutes = 10.0
        var workoutMinutes = 30.0
        var workoutActivity = WorkoutActivity.any
        var coordinate: CLLocationCoordinate2D?
        var radius = 150.0
        var dwellMinutes = 30.0
        var placeName = ""
        switch rule {
        case .manual: break
        case .healthQuantity(let m, let t): metric = m; quantityTarget = t
        case .healthSleep(let h): sleepHours = h
        case .healthMindful(let m): mindfulMinutes = m
        case .healthWorkout(let raw, let m): workoutActivity = WorkoutActivity.from(raw: raw); workoutMinutes = m
        case .geofence(let lat, let lon, let r, let d, let p):
            coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon); radius = r; dwellMinutes = d; placeName = p
        }
        _metric = State(initialValue: metric)
        _quantityTarget = State(initialValue: quantityTarget)
        _sleepHours = State(initialValue: sleepHours)
        _mindfulMinutes = State(initialValue: mindfulMinutes)
        _workoutMinutes = State(initialValue: workoutMinutes)
        _workoutActivity = State(initialValue: workoutActivity)
        _coordinate = State(initialValue: coordinate)
        _radius = State(initialValue: radius)
        _dwellMinutes = State(initialValue: dwellMinutes)
        _placeName = State(initialValue: placeName)
    }

    private var rule: HabitRule? {
        switch kind {
        case .manual: return .manual
        case .healthQuantity: return .healthQuantity(metric: metric, target: quantityTarget)
        case .healthSleep: return .healthSleep(minHours: sleepHours)
        case .healthMindful: return .healthMindful(minMinutes: mindfulMinutes)
        case .healthWorkout: return .healthWorkout(activityRaw: workoutActivity.healthKitType?.rawValue, minMinutes: workoutMinutes)
        case .geofence:
            guard let coordinate else { return nil }
            return .geofence(latitude: coordinate.latitude, longitude: coordinate.longitude, radius: radius,
                             minDwellMinutes: dwellMinutes, placeName: placeName.isEmpty ? String(localized: "Place") : placeName)
        case .screenTime: return nil
        }
    }

    private var geofenceLimitReached: Bool {
        guard kind == .geofence, existing?.kind != .geofence else { return false }
        let count = ((try? env.repository.activeHabits()) ?? []).filter { $0.kind == .geofence }.count
        return count >= LocationProvider.maxRegions
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && rule != nil && !geofenceLimitReached
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Habit") {
                    HStack {
                        TextField("Emoji", text: $emoji)
                            .frame(width: 44)
                            .multilineTextAlignment(.center)
                            .onChange(of: emoji) { _, new in emoji = String(new.suffix(1)) }
                        TextField("Name", text: $name)
                    }
                    ColorPaletteRow(selected: $colorHex)
                }

                Section("How is it tracked?") {
                    Picker("Source", selection: $kind) {
                        ForEach(HabitSourceKind.selectable, id: \.self) { kind in
                            Label(kind.displayName, systemImage: kind.systemImage).tag(kind)
                        }
                    }
                    sourceHint
                }

                sourceConfiguration

                if rule?.withTarget(rule?.target ?? 0) != nil {
                    Section {
                        Picker("Adaptive goal", selection: $adaptationMode) {
                            ForEach(GoalAdaptationMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                    } footer: {
                        Text(adaptationMode.explanation)
                    }
                }

                SchedulePickerSection(schedule: $schedule)

                Section {
                    Picker("Headline", selection: $progressModel) {
                        ForEach(ProgressModel.allCases, id: \.self) { model in
                            Text(model.displayName).tag(model)
                        }
                    }
                } header: {
                    Text("Progress")
                } footer: {
                    Text(progressModel.explanation)
                }
            }
            .navigationTitle(Text(existing == nil ? "New habit" : "Edit habit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(!canSave) }
            }
            .sheet(isPresented: $showPlacePicker) {
                PlacePickerView(coordinate: $coordinate, radius: $radius, placeName: $placeName)
            }
        }
    }

    @ViewBuilder
    private var sourceHint: some View {
        switch kind {
        case .manual: Text("You tap it. Good for things no sensor can see.").font(.footnote).foregroundStyle(.secondary)
        case .healthQuantity, .healthSleep, .healthMindful, .healthWorkout:
            Text("Completed automatically from Health. Background updates for steps arrive about once an hour.")
                .font(.footnote).foregroundStyle(.secondary)
        case .geofence:
            Text("Completed when you stay at the place long enough. Needs “Always” location for background detection.")
                .font(.footnote).foregroundStyle(.secondary)
        case .screenTime: EmptyView()
        }
    }

    @ViewBuilder
    private var sourceConfiguration: some View {
        switch kind {
        case .manual, .screenTime:
            EmptyView()
        case .healthQuantity:
            Section("Goal") {
                Picker("Metric", selection: $metric) {
                    ForEach(HealthMetric.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .onChange(of: metric) { _, new in quantityTarget = new.defaultTarget }
                Stepper(value: $quantityTarget, in: metric.stepIncrement...(metric.defaultTarget * 10), step: metric.stepIncrement) {
                    Text("At least \(ValueFormatting.value(quantityTarget, unit: metric.unitLabel)) \(metric.localizedUnit)")
                }
            }
        case .healthSleep:
            Section("Goal") {
                Stepper(value: $sleepHours, in: 4...12, step: 0.5) {
                    Text("At least \(ValueFormatting.value(sleepHours, unit: "h")) \(ValueFormatting.unit("h")) asleep")
                }
                Text("Counted from the night before the day starts.").font(.footnote).foregroundStyle(.secondary)
            }
        case .healthMindful:
            Section("Goal") {
                Stepper(value: $mindfulMinutes, in: 1...120, step: 1) {
                    Text("At least \(Int(mindfulMinutes)) mindful minutes")
                }
            }
        case .healthWorkout:
            Section("Goal") {
                Picker("Activity", selection: $workoutActivity) {
                    ForEach(WorkoutActivity.allCases) { Text($0.displayName).tag($0) }
                }
                Stepper(value: $workoutMinutes, in: 5...240, step: 5) {
                    Text("A workout of at least \(Int(workoutMinutes)) min")
                }
            }
        case .geofence:
            Section("Place") {
                Button {
                    showPlacePicker = true
                } label: {
                    HStack {
                        Label(placeTitle, systemImage: "mappin.and.ellipse")
                        Spacer()
                        if let coordinate {
                            Text(String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude))
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
                Stepper(value: $dwellMinutes, in: 1...240, step: 5) {
                    Text("Stay at least \(Int(dwellMinutes)) min")
                }
                Text("Radius \(Int(radius)) m").font(.footnote).foregroundStyle(.secondary)
                if geofenceLimitReached {
                    Label("iOS allows at most \(LocationProvider.maxRegions) place habits.", systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(.orange)
                }
            }
        }
    }

    private var placeTitle: String {
        if coordinate == nil { return String(localized: "Choose a place") }
        return placeName.isEmpty ? String(localized: "Place selected") : placeName
    }

    private func save() {
        guard let rule else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let habit: Habit
        if let existing {
            habit = existing
            habit.name = trimmed
            habit.emoji = emoji.isEmpty ? "✅" : emoji
            habit.colorHex = colorHex
            habit.rule = rule
            habit.schedule = schedule
            habit.progressModel = progressModel
            habit.adaptationMode = adaptationMode
            habit.updatedAt = Date()
        } else {
            let count = (try? env.repository.activeHabits().count) ?? 0
            habit = Habit(name: trimmed, emoji: emoji.isEmpty ? "✅" : emoji, colorHex: colorHex, rule: rule,
                          schedule: schedule, progressModel: progressModel, sortOrder: count)
            habit.adaptationMode = adaptationMode
            env.repository.insert(habit)
        }
        do {
            try env.repository.save()
        } catch {
            Log.app.error("Save failed: \(error.localizedDescription)")
        }
        env.habitDidChange(habit)
        dismiss()
    }
}

extension GoalAdaptationMode {
    var displayName: String {
        switch self {
        case .off: return String(localized: "Fixed")
        case .suggest: return String(localized: "Suggest changes")
        case .automatic: return String(localized: "Adjust automatically")
        }
    }

    var explanation: String {
        switch self {
        case .off: return String(localized: "The goal never changes on its own.")
        case .suggest: return String(localized: "When you consistently overshoot or fall short, HabitFlow offers a new goal. You decide.")
        case .automatic: return String(localized: "HabitFlow adjusts the goal itself and tells you what changed. At most one change every two weeks.")
        }
    }
}

extension HabitSourceKind {
    var displayName: String {
        switch self {
        case .manual: return String(localized: "Manual")
        case .healthQuantity: return String(localized: "Health metric")
        case .healthSleep: return String(localized: "Sleep")
        case .healthMindful: return String(localized: "Mindfulness")
        case .healthWorkout: return String(localized: "Workout")
        case .geofence: return String(localized: "Place")
        case .screenTime: return String(localized: "Screen Time")
        }
    }

    var systemImage: String {
        switch self {
        case .manual: return "hand.tap"
        case .healthQuantity: return "heart.text.square"
        case .healthSleep: return "bed.double"
        case .healthMindful: return "brain.head.profile"
        case .healthWorkout: return "figure.run"
        case .geofence: return "mappin.and.ellipse"
        case .screenTime: return "hourglass"
        }
    }
}

struct ColorPaletteRow: View {
    @Binding var selected: String

    var body: some View {
        HStack(spacing: 10) {
            ForEach(HabitPalette.hexes, id: \.self) { hex in
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: 28, height: 28)
                    .overlay {
                        if hex == selected {
                            Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                        }
                    }
                    .onTapGesture { selected = hex }
                    .accessibilityLabel("Color \(hex)")
            }
        }
        .padding(.vertical, 4)
    }
}

/// Picks between the two families of schedule: days the habit is named for, and a quota the
/// user spends on whichever days suit them.
struct SchedulePickerSection: View {
    @Binding var schedule: HabitSchedule

    /// The tab, kept apart from the value so switching back and forth does not lose the count.
    private enum Mode: String, CaseIterable, Identifiable {
        case days, quota, interval
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .days: return "Days"
            case .quota: return "Times"
            case .interval: return "Interval"
            }
        }
    }

    private var mode: Mode {
        switch schedule {
        case .everyDay, .weekdays: return .days
        case .timesPerWeek, .timesPerMonth: return .quota
        case .everyXDays: return .interval
        }
    }

    private var mask: Binding<Int> {
        Binding(get: { schedule.legacyMask }, set: { schedule = .weekdays(mask: $0) })
    }

    var body: some View {
        Section {
            Picker("Schedule", selection: Binding(get: { mode }, set: { switchTo($0) })) {
                ForEach(Mode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            switch schedule {
            case .everyDay, .weekdays:
                WeekdayPicker(mask: mask)
            case .timesPerWeek(let count):
                Stepper(value: Binding(get: { count }, set: { schedule = .timesPerWeek(count: $0) }), in: 1...7) {
                    Text("\(count) times a week")
                }
            case .timesPerMonth(let count):
                Stepper(value: Binding(get: { count }, set: { schedule = .timesPerMonth(count: $0) }), in: 1...31) {
                    Text("\(count) times a month")
                }
            case .everyXDays(let interval):
                Stepper(value: Binding(get: { interval }, set: { schedule = .everyXDays(interval: $0) }), in: 2...30) {
                    Text("Every \(interval) days")
                }
            }

            if schedule.isFlexible {
                Picker("Period", selection: periodChoice) {
                    Text("Per week").tag(SchedulePeriod.week)
                    Text("Per month").tag(SchedulePeriod.month)
                }
            }
        } header: {
            Text("Schedule")
        } footer: {
            Text(explanation)
        }
    }

    private var periodChoice: Binding<SchedulePeriod> {
        Binding(
            get: { schedule.period },
            set: { period in
                let count = schedule.quota
                schedule = period == .week ? .timesPerWeek(count: min(count, 7)) : .timesPerMonth(count: count)
            }
        )
    }

    private var explanation: LocalizedStringKey {
        switch schedule {
        case .everyDay, .weekdays:
            return "Due on the days you pick. A day you skip counts as a miss."
        case .timesPerWeek, .timesPerMonth:
            return "Any days you like, as long as the count adds up. Streaks count periods, not days."
        case .everyXDays:
            return "Counted from the day the habit was created."
        }
    }

    private func switchTo(_ mode: Mode) {
        switch mode {
        case .days: schedule = .everyDay
        case .quota: schedule = .timesPerWeek(count: 3)
        case .interval: schedule = .everyXDays(interval: 2)
        }
    }
}

struct WeekdayPicker: View {
    @Binding var mask: Int
    private let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols  // Sunday first

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<7, id: \.self) { index in
                let on = mask & (1 << index) != 0
                Text(symbols[index])
                    .font(.footnote.weight(.semibold))
                    .frame(width: 34, height: 34)
                    .background(on ? Color.accentColor : Color.secondary.opacity(0.15), in: Circle())
                    .foregroundStyle(on ? .white : .primary)
                    .onTapGesture {
                        if on { mask &= ~(1 << index) } else { mask |= (1 << index) }
                    }
                    .accessibilityLabel(Calendar.current.standaloneWeekdaySymbols[index])
                    .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}
