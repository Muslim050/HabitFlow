import Foundation
import Observation
import HabitCore

/// Observable wrapper around `AnalysisEngine`: keeps the latest result for the UI and
/// throttles recomputation, since the tracking engine runs every minute in the foreground.
@MainActor
@Observable
final class AnalysisService {
    private let engine: AnalysisEngine
    private let minimumInterval: TimeInterval = 5 * 60

    private(set) var insights: [Insight] = []
    private(set) var proposals: [GoalProposal] = []
    private(set) var lastComputedAt: Date?

    init(repository: any HabitRepository, settings: AppSettings, clock: @escaping () -> Date = Date.init) {
        engine = AnalysisEngine(repository: repository, settings: settings, clock: clock)
    }

    func refreshIfNeeded(force: Bool = false) {
        let now = engine.clock()
        if !force, let last = lastComputedAt, now.timeIntervalSince(last) < minimumInterval { return }
        refresh()
    }

    func refresh() {
        let result = engine.refresh()
        insights = result.insights
        proposals = result.proposals
        // An automatic change surfaces to the user as a `goalChanged` insight.
        for change in result.automaticChanges {
            Log.app.info("Goal adapted automatically: \(change.currentTarget) -> \(change.proposedTarget)")
        }
        lastComputedAt = engine.clock()
    }

    func apply(_ proposal: GoalProposal) {
        engine.apply(proposal)
        proposals.removeAll { $0.habitID == proposal.habitID }
        refresh()
    }

    func dismiss(_ proposal: GoalProposal) {
        engine.dismiss(proposal)
        proposals.removeAll { $0.habitID == proposal.habitID }
    }

    func habitName(_ id: UUID?) -> String { habit(id)?.name ?? "" }

    func habit(_ id: UUID?) -> Habit? {
        guard let id else { return nil }
        return try? engine.repository.habit(id: id)
    }

    func insights(for habitID: UUID) -> [Insight] {
        insights.filter { $0.habitID == habitID || $0.relatedHabitID == habitID }
    }

    func proposal(for habitID: UUID) -> GoalProposal? {
        proposals.first { $0.habitID == habitID }
    }
}
