import SwiftData
import SwiftUI
import HabitCore

struct HabitDetailView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Query private var logs: [DailyLog]
    @Query private var pauses: [HabitPause]
    let habit: Habit
    @State private var showEditor = false
    @State private var confirmArchive = false
    @State private var editingDay: DayKey?
    @State private var showPause = false

    init(habit: Habit) {
        self.habit = habit
        let id = habit.id
        _logs = Query(filter: #Predicate<DailyLog> { $0.habitID == id }, sort: [SortDescriptor(\DailyLog.dayKey)])
    }

    private var stats: HabitStats {
        _ = env.evaluationTick
        return HabitStats.compute(
            habit: habit, logs: logs, calendar: env.settings.dayCalendar,
            today: env.currentDayKey, freezesPerMonth: env.settings.freezesPerMonth, pauses: pauses
        )
    }

    private var todayLog: DailyLog? { logs.first { $0.dayKey == env.currentDayKey.raw } }

    private var color: Color { Color(hex: habit.colorHex) }

    /// The pause covering today, if any. A global one counts: it is why this habit is quiet.
    private var runningPause: HabitPause? {
        let today = env.currentDayKey
        return pauses.first { ($0.habitID == nil || $0.habitID == habit.id) && $0.span.contains(today) }
    }

    /// Days the heat map hands to the editor: inside the backdating window and after the habit existed.
    private var editableRange: ClosedRange<DayKey> {
        let editable = env.engine.editableDayRange()
        let earliest = max(editable.lowerBound, env.settings.dayCalendar.dayKey(for: habit.createdAt))
        return earliest <= editable.upperBound ? earliest...editable.upperBound : editable
    }

    var body: some View {
        let stats = stats
        List {
            Section {
                HStack(spacing: 16) {
                    ProgressRing(ratio: todayLog?.ratio ?? 0, color: color, lineWidth: 7, completed: todayLog?.isCompleted ?? false) {
                        Text(habit.emoji).font(.largeTitle)
                    }
                    .frame(width: 84, height: 84)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(habit.name).font(.title2.bold())
                        if habit.isAutomatic {
                            Text(todayLog.map { ValueFormatting.progress(value: $0.progressValue, target: $0.targetValue, unit: habit.rule.unitLabel) }
                                 ?? ValueFormatting.goal(target: habit.rule.target, unit: habit.rule.unitLabel))
                                .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                            if let source = habit.rule.sourceLabel {
                                Label("Auto from \(source)", systemImage: habit.rule.systemImage)
                                    .font(.caption).foregroundStyle(color)
                            }
                        } else {
                            Text("Manual habit").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 6)
            }

            Section {
                let headline = ProgressHeadline(stats: stats, freezesPerMonth: env.settings.freezesPerMonth,
                                                today: env.currentDayKey)
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline.value).font(.system(.largeTitle, design: .rounded).weight(.semibold).monospacedDigit())
                    Text(headline.title).font(.subheadline).foregroundStyle(.secondary)
                    if let detail = headline.detail {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }

            Section("Stats") {
                // A streak is counted in the schedule's own unit: three times a week makes weeks,
                // not days, so the number is meaningless without the word beside it.
                StatRow(title: "Current streak", value: SchedulePeriodText.length(stats.currentStreak.length, stats.period),
                        detail: stats.currentStreak.gracesUsed > 0 ? String(localized: "\(stats.currentStreak.gracesUsed) frozen") : nil)
                StatRow(title: "Best streak", value: SchedulePeriodText.length(stats.bestStreak, stats.period), detail: nil)
                StatRow(title: "Strength", value: String(localized: "\(stats.habitScore) / 100"), detail: nil)
                StatRow(title: "Consistency",
                        value: stats.consistency.score.map { String(localized: "\($0) / 100") } ?? String(localized: "Warming up"),
                        detail: stats.consistency.score == nil
                            ? String(localized: "\(stats.consistency.history) of \(stats.consistency.minimum) needed")
                            : String(localized: "Recent periods weigh more"))
                StatRow(title: "Completed", value: String(localized: "\(stats.completedCount) of \(stats.requiredCount)"), detail: nil)
            }

            Section("Last 16 weeks") {
                HeatmapView(
                    results: stats.results, color: color, weeks: 16,
                    calendar: env.settings.dayCalendar, today: env.currentDayKey,
                    frozen: stats.frozenDays,
                    editable: editableRange, onSelect: { editingDay = $0 }
                )
                .padding(.vertical, 4)
                Button {
                    editingDay = env.currentDayKey
                } label: { Label("Edit a day", systemImage: "calendar.badge.clock") }
                    .font(.subheadline)
            }

            if let proposal = env.analysis.proposal(for: habit.id) {
                Section("Goal suggestion") {
                    GoalProposalCard(proposal: proposal)
                }
            }

            let habitInsights = env.analysis.insights(for: habit.id)
            if !habitInsights.isEmpty {
                Section("Patterns") {
                    ForEach(habitInsights) { insight in
                        InsightCard(presentation: InsightPresentation(
                            insight: insight,
                            habitName: env.analysis.habitName(insight.habitID),
                            relatedName: env.analysis.habitName(insight.relatedHabitID),
                            rule: habit.rule
                        ))
                    }
                }
            }

            Section("Pause") {
                if let running = runningPause {
                    PauseRow(pause: running)
                } else {
                    Button { showPause = true } label: {
                        Label("Pause this habit", systemImage: "pause.circle")
                    }
                }
            }

            Section {
                if habit.isAutomatic {
                    Button {
                        try? env.engine.setManualCompletion(habitID: habit.id, completed: !(todayLog?.isCompleted ?? false))
                    } label: {
                        Label((todayLog?.isCompleted ?? false) ? "Mark today not done" : "Mark today done",
                              systemImage: (todayLog?.isCompleted ?? false) ? "xmark.circle" : "checkmark.circle")
                    }
                    if todayLog?.completionSource == .manualOverride {
                        Button {
                            Task { try? await env.engine.clearOverride(habitID: habit.id) }
                        } label: { Label("Let auto-tracking decide today", systemImage: "arrow.clockwise") }
                    }
                }
                Button(role: .destructive) { confirmArchive = true } label: { Label("Archive habit", systemImage: "archivebox") }
            }
        }
        .navigationTitle(habit.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button("Edit") { showEditor = true } }
        }
        .sheet(isPresented: $showEditor) { HabitEditorView(habit: habit) }
        .sheet(isPresented: $showPause) { PauseSheet(habit: habit) }
        .sheet(item: $editingDay) { day in
            DayEditorView(habit: habit, dayKey: day, calendar: env.settings.dayCalendar)
        }
        .task { env.analysis.refreshIfNeeded() }
        .confirmationDialog("Archive this habit? History is kept.", isPresented: $confirmArchive, titleVisibility: .visible) {
            Button("Archive", role: .destructive) {
                habit.archivedAt = Date()
                habit.updatedAt = Date()
                try? env.repository.save()
                env.habitDidChange(nil)
                dismiss()
            }
        }
    }
}

struct StatRow: View {
    let title: LocalizedStringKey
    let value: String
    let detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Text(value).font(.body.monospacedDigit().weight(.semibold))
        }
    }
}
