import SwiftData
import SwiftUI
import HabitCore

struct TodayView: View {
    @Environment(AppEnvironment.self) private var env
    @Query private var habits: [Habit]
    @Query private var logs: [DailyLog]
    @Query private var pauses: [HabitPause]
    let dayKey: DayKey
    let onAdd: () -> Void

    init(dayKey: DayKey, onAdd: @escaping () -> Void = {}) {
        self.dayKey = dayKey
        self.onAdd = onAdd
        let raw = dayKey.raw
        _habits = Query(
            filter: #Predicate<Habit> { $0.archivedAt == nil },
            sort: [SortDescriptor(\Habit.sortOrder), SortDescriptor(\Habit.createdAt)]
        )
        _logs = Query(filter: #Predicate<DailyLog> { $0.dayKey == raw })
    }

    /// Every habit the day can take: named by the schedule, or inside a period whose quota
    /// is still open to any day.
    private var scheduledHabits: [Habit] {
        let calendar = env.settings.dayCalendar
        return habits.filter { $0.isDue(on: dayKey, calendar: calendar, pauses: pauses.spans(for: $0.id)) }
    }

    /// The pause covering the whole app today, if any — worth saying out loud, because
    /// otherwise the list is empty for no visible reason.
    var globalPause: PauseSpan? { pauses.globalSpans.span(on: dayKey) }

    private func log(for habit: Habit) -> DailyLog? {
        logs.first { $0.habitID == habit.id }
    }

    var body: some View {
        let scheduled = scheduledHabits
        let completed = scheduled.filter { log(for: $0)?.isCompleted == true }.count

        ScrollView {
            LazyVStack(spacing: 14) {
                topBar

                TodayHeaderView(
                    completed: completed,
                    total: scheduled.count,
                    lastRun: env.settings.lastEngineRunAt,
                    isPaused: globalPause != nil
                )

                if env.isUsingFallbackStore {
                    Label("No shared storage — the widget will not update.", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(HFTheme.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .hfCard(color: HFTheme.orangeSoft)
                }

                if let pause = globalPause {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Everything is paused").font(.subheadline.weight(.semibold))
                            Text(pause.end.map {
                                String(localized: "Until \($0.formatted(calendar: env.settings.dayCalendar))")
                            } ?? String(localized: "Until you resume it"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: pause.reason.systemImage)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .hfCard(color: HFTheme.blueSoft)
                }

                if !env.analysis.proposals.isEmpty {
                    HFSectionHeader(title: "Goal suggestions", detail: "Based on your rhythm")
                        .padding(.top, 8)
                    ForEach(env.analysis.proposals) { proposal in
                        GoalProposalCard(proposal: proposal)
                    }
                }

                if scheduled.isEmpty && globalPause == nil {
                    ContentUnavailableView(
                        habits.isEmpty ? "No habits yet" : "Nothing scheduled today",
                        systemImage: "sparkles",
                        description: Text(habits.isEmpty
                            ? "Add a habit and let Health or your location complete it for you."
                            : "Enjoy the day off.")
                    )
                    .frame(maxWidth: .infinity)
                    .hfCard(padding: 26)
                } else if !scheduled.isEmpty {
                    HFSectionHeader(title: "In focus", detail: "\(completed) of \(scheduled.count) done")
                        .padding(.top, 8)
                    ForEach(scheduled) { habit in
                        HabitRowView(habit: habit, log: log(for: habit))
                    }
                }

                if env.settings.agendaEnabled {
                    HFSectionHeader(title: "Also today")
                        .padding(.top, 8)
                    AgendaSection()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .hfCard()
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 112)
        }
        .background(HFTheme.background.ignoresSafeArea())
        .refreshable {
            await env.engine.evaluateAll(reason: .manualRefresh)
            env.analysis.refresh()
        }
        .task { env.analysis.refreshIfNeeded() }
    }

    private var topBar: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 3) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(HFTheme.secondaryInk)
                Text("Today")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .tracking(-1.2)
                    .foregroundStyle(HFTheme.ink)
            }
            Spacer()
            HFIconButton(systemImage: "plus", accessibilityTitle: "Add habit", action: onAdd)
        }
        .padding(.bottom, 4)
    }
}

struct TodayHeaderView: View {
    let completed: Int
    let total: Int
    let lastRun: Date?
    /// Everything is paused, so an empty list means "on hold", not "nothing set up yet".
    var isPaused = false

    private var headline: LocalizedStringKey {
        if isPaused { return "On hold" }
        if total == 0 { return "Add your first habit" }
        if completed == total { return "All done for today" }
        if total - completed == 1 { return "One step left" }
        return "\(total - completed) habits left"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Your rhythm today")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(HFTheme.accent)
                Text(headline)
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .tracking(-0.6)
                    .foregroundStyle(HFTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 14)
                HStack(spacing: 8) {
                    Circle()
                        .fill(HFTheme.accent)
                        .frame(width: 7, height: 7)
                        .shadow(color: HFTheme.accent.opacity(0.25), radius: 5)
                    if total == 0 {
                        Text("Health and places can complete it for you")
                    } else if let lastRun {
                        Text("Auto-tracking checked \(lastRun, style: .relative) ago")
                    } else {
                        Text("Pull down to check Health and places now")
                    }
                }
                .font(.caption2)
                .foregroundStyle(HFTheme.secondaryInk)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(HFTheme.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            Spacer(minLength: 4)
            if total == 0 {
                Image(systemName: "sparkles")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(HFTheme.accent)
                    .frame(width: 66, height: 66)
                    .background(HFTheme.surface.opacity(0.72), in: Circle())
                    .overlay { Circle().stroke(HFTheme.accent.opacity(0.12), lineWidth: 1) }
            } else {
                ProgressRing(
                    ratio: Double(completed) / Double(total),
                    color: HFTheme.accent,
                    lineWidth: 7,
                    completed: completed == total
                ) {
                    Text("\(completed)/\(total)")
                        .font(.headline.monospacedDigit().bold())
                        .foregroundStyle(HFTheme.ink)
                }
                .frame(width: 68, height: 68)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 136, alignment: .leading)
        .padding(20)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [HFTheme.sage, HFTheme.surface],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                FlowWaveShape()
                    .stroke(HFTheme.accent.opacity(0.07), style: StrokeStyle(lineWidth: 30, lineCap: .round))
                    .offset(y: 28)
                FlowWaveShape()
                    .stroke(HFTheme.lime.opacity(0.22), style: StrokeStyle(lineWidth: 11, lineCap: .round))
                    .offset(x: 70, y: -44)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .allowsHitTesting(false)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(HFTheme.accent.opacity(0.10), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .shadow(color: HFTheme.ink.opacity(0.045), radius: 16, y: 7)
        .accessibilityElement(children: .combine)
    }
}

private struct FlowWaveShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: -rect.width * 0.12, y: rect.height * 0.78))
        path.addCurve(
            to: CGPoint(x: rect.width * 1.12, y: rect.height * 0.24),
            control1: CGPoint(x: rect.width * 0.30, y: rect.height * 1.05),
            control2: CGPoint(x: rect.width * 0.67, y: -rect.height * 0.08)
        )
        return path
    }
}
