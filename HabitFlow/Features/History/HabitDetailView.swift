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
        ScrollView {
            LazyVStack(spacing: 14) {
                detailTopBar
                habitHero
                rhythmCard(stats)

                HFSectionHeader(title: "Last 16 weeks", detail: "Tap a day to edit")
                    .padding(.top, 8)
                HeatmapView(
                    results: stats.results, color: color, weeks: 16,
                    calendar: env.settings.dayCalendar, today: env.currentDayKey,
                    frozen: stats.frozenDays,
                    editable: editableRange, onSelect: { editingDay = $0 }
                )
                .padding(.vertical, 3)
                .hfCard()

                if let proposal = env.analysis.proposal(for: habit.id) {
                    HFSectionHeader(title: "Smart goal", detail: "A gentle suggestion")
                        .padding(.top, 8)
                    GoalProposalCard(proposal: proposal)
                }

                let habitInsights = env.analysis.insights(for: habit.id)
                if !habitInsights.isEmpty {
                    HFSectionHeader(title: "What helps", detail: "From your history")
                        .padding(.top, 8)
                    ForEach(habitInsights) { insight in
                        InsightCard(presentation: InsightPresentation(
                            insight: insight,
                            habitName: env.analysis.habitName(insight.habitID),
                            relatedName: env.analysis.habitName(insight.relatedHabitID),
                            rule: habit.rule
                        ))
                    }
                }

                HFSectionHeader(title: "Details")
                    .padding(.top, 8)
                statsCard(stats)

                VStack(spacing: 0) {
                    if let running = runningPause {
                        PauseRow(pause: running)
                            .padding(.vertical, 3)
                    } else {
                        Button { showPause = true } label: {
                            actionRow("Pause this habit", systemImage: "pause.circle")
                        }
                    }

                    if habit.isAutomatic {
                        Divider().overlay(HFTheme.divider)
                        Button {
                            try? env.engine.setManualCompletion(habitID: habit.id, completed: !(todayLog?.isCompleted ?? false))
                        } label: {
                            actionRow(
                                (todayLog?.isCompleted ?? false) ? "Mark today not done" : "Mark today done",
                                systemImage: (todayLog?.isCompleted ?? false) ? "xmark.circle" : "checkmark.circle"
                            )
                        }
                        if todayLog?.completionSource == .manualOverride {
                            Divider().overlay(HFTheme.divider)
                            Button {
                                Task { try? await env.engine.clearOverride(habitID: habit.id) }
                            } label: {
                                actionRow("Let auto-tracking decide today", systemImage: "arrow.clockwise")
                            }
                        }
                    }
                    Divider().overlay(HFTheme.divider)
                    Button(role: .destructive) { confirmArchive = true } label: {
                        actionRow("Archive habit", systemImage: "archivebox", color: .red)
                    }
                }
                .buttonStyle(.plain)
                .hfCard(padding: 10)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 112)
        }
        .background(HFTheme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
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

    private var detailTopBar: some View {
        HStack {
            HFIconButton(systemImage: "chevron.left", accessibilityTitle: "Back") { dismiss() }
            Spacer()
            Menu {
                Button { showEditor = true } label: { Label("Edit", systemImage: "pencil") }
                Button { editingDay = env.currentDayKey } label: { Label("Edit a day", systemImage: "calendar.badge.clock") }
                Button { showPause = true } label: { Label("Pause this habit", systemImage: "pause.circle") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(HFTheme.ink)
                    .frame(width: 44, height: 44)
                    .background(HFTheme.surfaceRaised, in: Circle())
                    .overlay { Circle().stroke(HFTheme.ink.opacity(0.06), lineWidth: 1) }
            }
        }
    }

    private var habitHero: some View {
        VStack(spacing: 12) {
            ProgressRing(
                ratio: todayLog?.ratio ?? 0,
                color: color,
                lineWidth: 8,
                completed: todayLog?.isCompleted ?? false
            ) {
                HabitIconView(habit: habit, size: 58)
            }
            .frame(width: 88, height: 88)

            VStack(spacing: 4) {
                Text(habit.name)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .tracking(-0.6)
                    .foregroundStyle(HFTheme.ink)
                if habit.isAutomatic {
                    Text(todayLog.map {
                        ValueFormatting.progress(value: $0.progressValue, target: $0.targetValue, unit: habit.rule.unitLabel)
                    } ?? ValueFormatting.goal(target: habit.rule.target, unit: habit.rule.unitLabel))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(HFTheme.secondaryInk)
                    if let source = habit.rule.sourceLabel {
                        Label("Auto from \(source)", systemImage: habit.rule.systemImage)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(HFTheme.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(HFTheme.sage, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                } else {
                    Text("Manual habit").font(.subheadline).foregroundStyle(HFTheme.secondaryInk)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func rhythmCard(_ stats: HabitStats) -> some View {
        let headline = ProgressHeadline(
            stats: stats,
            freezesPerMonth: env.settings.freezesPerMonth,
            today: env.currentDayKey
        )
        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(headline.value)
                    .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                    .tracking(-1.2)
                    .foregroundStyle(HFTheme.ink)
                Text(headline.title).font(.subheadline.weight(.semibold)).foregroundStyle(HFTheme.ink)
                if let detail = headline.detail {
                    Text(detail).font(.caption).foregroundStyle(HFTheme.secondaryInk)
                }
            }
            Spacer()
            Image(systemName: "waveform.path.ecg")
                .font(.title2.weight(.semibold))
                .foregroundStyle(HFTheme.accent)
                .frame(width: 52, height: 52)
                .background(HFTheme.sage, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .accessibilityElement(children: .combine)
        .hfCard()
    }

    private func statsCard(_ stats: HabitStats) -> some View {
        VStack(spacing: 0) {
            StatRow(
                title: "Current streak",
                value: SchedulePeriodText.length(stats.currentStreak.length, stats.period),
                detail: stats.currentStreak.gracesUsed > 0 ? String(localized: "\(stats.currentStreak.gracesUsed) frozen") : nil
            )
            Divider().overlay(HFTheme.divider)
            StatRow(title: "Best streak", value: SchedulePeriodText.length(stats.bestStreak, stats.period), detail: nil)
            Divider().overlay(HFTheme.divider)
            StatRow(title: "Strength", value: String(localized: "\(stats.habitScore) / 100"), detail: nil)
            Divider().overlay(HFTheme.divider)
            StatRow(
                title: "Consistency",
                value: stats.consistency.score.map { String(localized: "\($0) / 100") } ?? String(localized: "Warming up"),
                detail: stats.consistency.score == nil
                    ? String(localized: "\(stats.consistency.history) of \(stats.consistency.minimum) needed")
                    : String(localized: "Recent periods weigh more")
            )
            Divider().overlay(HFTheme.divider)
            StatRow(title: "Completed", value: String(localized: "\(stats.completedCount) of \(stats.requiredCount)"), detail: nil)
        }
        .hfCard(padding: 10)
    }

    private func actionRow(
        _ title: LocalizedStringKey,
        systemImage: String,
        color: Color = HFTheme.ink
    ) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 11)
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
        .padding(.horizontal, 6)
        .padding(.vertical, 11)
    }
}
