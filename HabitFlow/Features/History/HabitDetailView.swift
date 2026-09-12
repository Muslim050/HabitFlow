import SwiftData
import SwiftUI
import HabitCore

struct HabitDetailView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Query private var logs: [DailyLog]
    let habit: Habit
    @State private var showEditor = false
    @State private var confirmArchive = false

    init(habit: Habit) {
        self.habit = habit
        let id = habit.id
        _logs = Query(filter: #Predicate<DailyLog> { $0.habitID == id }, sort: [SortDescriptor(\DailyLog.dayKey)])
    }

    private var stats: HabitStats {
        _ = env.evaluationTick
        return HabitStats.compute(
            habit: habit, logs: logs, calendar: env.settings.dayCalendar,
            today: env.currentDayKey, graceMissesPerWeek: env.settings.graceMissesPerWeek
        )
    }

    private var todayLog: DailyLog? { logs.first { $0.dayKey == env.currentDayKey.raw } }
    private var color: Color { Color(hex: habit.colorHex) }

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

            Section("Stats") {
                StatRow(title: "Current streak", value: String(localized: "\(stats.currentStreak.length) days"),
                        detail: stats.currentStreak.gracesUsed > 0 ? String(localized: "\(stats.currentStreak.gracesUsed) forgiven misses") : nil)
                StatRow(title: "Best streak", value: String(localized: "\(stats.bestStreak) days"), detail: nil)
                StatRow(title: "Consistency",
                        value: stats.consistency.score.map { String(localized: "\($0) / 100") } ?? String(localized: "Warming up"),
                        detail: stats.consistency.score == nil
                            ? String(localized: "\(stats.consistency.historyDays)/\(ConsistencyScore.minimumHistoryDays) days of history")
                            : String(localized: "Last 30 days, recent days weigh more"))
                StatRow(title: "Completed", value: String(localized: "\(stats.completedDays) of \(stats.scheduledDays)"), detail: nil)
            }

            Section("Last 16 weeks") {
                HeatmapView(results: stats.results, color: color, weeks: 16, calendar: env.settings.dayCalendar, today: env.currentDayKey)
                    .padding(.vertical, 4)
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
