import Foundation

/// How a habit reports its progress. The classic consecutive streak is one option among four,
/// not the frame everything else hangs off: zeroing a long run after a single missed day is the
/// commonest reason people abandon a tracker, and skipping one day does not undo a habit.
public enum ProgressModel: String, Codable, CaseIterable, Sendable, Hashable {
    /// Exponential moving average of kept obligations, 0…100. Rises with repetition, dips on a
    /// miss, never resets. The default.
    case habitScore
    /// Consecutive kept obligations, freezes included.
    case consecutiveStreak
    /// Share of obligations kept over the recent window.
    case completionRate
    /// Every obligation ever kept.
    case totalCompletions

    public static let `default` = ProgressModel.habitScore
}

/// Loop-style habit strength: an exponential moving average over obligations, 0…100.
public enum HabitScore {
    /// Obligations needed to close half the distance to a new level. Thirteen makes a single
    /// miss cost a few points near the top and a month of work to reach it — which is the point.
    /// A score is not a streak: it should be slow in both directions.
    public static let halfLife: Double = 13

    /// `obligations` ascending. A still-running obligation counts only once fulfilled, so an
    /// unfinished week never drags the number down mid-week.
    public static func compute(_ obligations: [ObligationResult], halfLife: Double = HabitScore.halfLife) -> Int {
        let judged = obligations.filter { !$0.isOpen || $0.fulfilled }
        guard !judged.isEmpty else { return 0 }
        let alpha = 1 - pow(0.5, 1 / max(halfLife, 1))
        var score = 0.0
        for obligation in judged {
            score += alpha * (obligation.credit - score)
        }
        return min(max(Int((score * 100).rounded()), 0), 100)
    }
}
