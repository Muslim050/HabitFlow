import Foundation

/// What one analysis pass produced.
public struct AnalysisResult: Sendable {
    public var insights: [Insight] = []
    public var proposals: [GoalProposal] = []
    /// Goals this pass changed on its own (habits set to `automatic`).
    public var automaticChanges: [GoalProposal] = []
    public init() {}
}

/// Reads history, produces insights and goal proposals, and applies adaptations for habits
/// set to `automatic`. Lives next to the store so it can be tested without a UI.
@MainActor
public final class AnalysisEngine {
    public let repository: any HabitRepository
    public let settings: AppSettings
    public var clock: () -> Date

    /// History older than this is ignored: long enough for weekday patterns, short enough to stay cheap.
    public static let historyWindowDays = 90
    /// A goal change is worth announcing for this long.
    public static let goalChangeNoticeDays = 3

    public init(repository: any HabitRepository, settings: AppSettings, clock: @escaping () -> Date = Date.init) {
        self.repository = repository
        self.settings = settings
        self.clock = clock
    }

    public func refresh() -> AnalysisResult {
        let now = clock()
        let calendar = settings.dayCalendar
        let today = calendar.dayKey(for: now)
        let from = calendar.key(byAdding: -(Self.historyWindowDays - 1), to: today)

        guard let habits = try? repository.activeHabits(), !habits.isEmpty,
              let allLogs = try? repository.logs(from: from, to: today) else {
            return AnalysisResult()
        }
        let logsByHabit = Dictionary(grouping: allLogs, by: \.habitID)

        var histories: [InsightEngine.HabitHistory] = []
        var result = AnalysisResult()

        for habit in habits {
            let logs = logsByHabit[habit.id] ?? []
            histories.append(HistoryBuilder.history(habit: habit, logs: logs, calendar: calendar,
                                                    today: today, windowDays: Self.historyWindowDays))

            let samples = HistoryBuilder.adaptationSamples(habit: habit, logs: logs, calendar: calendar, today: today)
            guard let proposal = GoalAdaptation.proposal(
                habitID: habit.id, rule: habit.rule, samples: samples, mode: habit.adaptationMode,
                lastChangeAt: habit.lastGoalChangeAt, lastDismissedAt: habit.lastProposalDismissedAt,
                now: now, calendar: calendar.calendar
            ) else { continue }

            if habit.adaptationMode == .automatic {
                habit.applyGoal(proposal.proposedTarget, at: now)
                result.automaticChanges.append(proposal)
            } else {
                result.proposals.append(proposal)
            }
        }

        var insights = InsightEngine.insights(for: histories, calendar: calendar, today: today)
        insights.append(contentsOf: recentGoalChanges(habits: habits, now: now))
        result.insights = insights.sorted { $0.priority > $1.priority }

        if !result.automaticChanges.isEmpty { try? repository.save() }
        return result
    }

    /// A goal that changed in the last few days becomes an insight, so a silent change is never a surprise.
    private func recentGoalChanges(habits: [Habit], now: Date) -> [Insight] {
        habits.compactMap { habit in
            guard let changedAt = habit.lastGoalChangeAt,
                  now.timeIntervalSince(changedAt) < Double(Self.goalChangeNoticeDays) * 24 * 3600 else { return nil }
            return Insight(kind: .goalChanged, habitID: habit.id, priority: 95,
                           primaryValue: habit.rule.target, unitLabel: habit.rule.unitLabel)
        }
    }

    // MARK: Acting on a proposal

    @discardableResult
    public func apply(_ proposal: GoalProposal) -> Bool {
        guard let habit = try? repository.habit(id: proposal.habitID) else { return false }
        habit.applyGoal(proposal.proposedTarget, at: clock())
        try? repository.save()
        return true
    }

    /// Starts the cooldown so the same suggestion does not come back tomorrow.
    @discardableResult
    public func dismiss(_ proposal: GoalProposal) -> Bool {
        guard let habit = try? repository.habit(id: proposal.habitID) else { return false }
        let now = clock()
        habit.lastProposalDismissedAt = now
        habit.updatedAt = now
        try? repository.save()
        return true
    }
}
