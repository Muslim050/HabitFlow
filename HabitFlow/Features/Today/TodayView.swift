import SwiftData
import SwiftUI
import HabitCore

struct TodayView: View {
    @Environment(AppEnvironment.self) private var env
    @Query private var habits: [Habit]
    @Query private var logs: [DailyLog]
    @Query private var pauses: [HabitPause]
    let dayKey: DayKey

    init(dayKey: DayKey) {
        self.dayKey = dayKey
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

        List {
            if env.isUsingFallbackStore {
                Section {
                    // The App Group is what the widget reads; without it the app still works.
                    Label("No shared storage — the widget will not update.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            if let pause = globalPause {
                // Without this the list is simply empty, which reads as a bug rather than a holiday.
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Everything is paused")
                            Text(pause.end.map {
                                String(localized: "Until \($0.formatted(calendar: env.settings.dayCalendar))")
                            } ?? String(localized: "Until you resume it"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: pause.reason.systemImage)
                    }
                }
            }
            Section {
                TodayHeaderView(completed: completed, total: scheduled.count,
                                lastRun: env.settings.lastEngineRunAt, isPaused: globalPause != nil)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            }
            if !env.analysis.proposals.isEmpty {
                Section("Goal suggestions") {
                    ForEach(env.analysis.proposals) { proposal in
                        GoalProposalCard(proposal: proposal)
                    }
                }
            }
            if scheduled.isEmpty && globalPause == nil {
                Section {
                    ContentUnavailableView(
                        habits.isEmpty ? "No habits yet" : "Nothing scheduled today",
                        systemImage: "sparkles",
                        description: Text(habits.isEmpty
                            ? "Add a habit and let Health or your location complete it for you."
                            : "Enjoy the day off.")
                    )
                }
            } else if !scheduled.isEmpty {
                Section("Habits") {
                    ForEach(scheduled) { habit in
                        HabitRowView(habit: habit, log: log(for: habit))
                    }
                }
            }

            if env.settings.agendaEnabled {
                Section {
                    AgendaSection()
                } header: {
                    Text("Also today")
                }
            }
        }
        .refreshable {
            await env.engine.evaluateAll(reason: .manualRefresh)
            env.analysis.refresh()
        }
        .task { env.analysis.refreshIfNeeded() }
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
        return completed == total ? "All done for today" : "\(total - completed) to go"
    }

    var body: some View {
        HStack(spacing: 16) {
            ProgressRing(ratio: total == 0 ? 0 : Double(completed) / Double(total), color: .accentColor, lineWidth: 8, completed: total > 0 && completed == total) {
                Text("\(completed)/\(total)")
                    .font(.headline.monospacedDigit())
            }
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text(headline).font(.headline)
                if let lastRun {
                    Text("Auto-tracking checked \(lastRun, style: .relative) ago")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Pull down to check Health and places now")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }
}
