import Foundation

/// A 0…100 recency-weighted completion index that replaces streak anxiety.
public enum ConsistencyScore {
    public static let minimumHistoryDays = 7

    public struct Result: Sendable, Equatable {
        public var score: Int?
        public var historyDays: Int
        public var isWarmingUp: Bool { score == nil }
    }

    /// `results` ascending; today is excluded unless completed. Missing history ⇒ `score == nil`.
    public static func compute(_ results: [DayResult], today: DayKey, windowDays: Int = 30, halfLifeDays: Double = 15) -> Result {
        let eligible = results
            .filter { $0.scheduled && $0.dayKey <= today }
            .filter { $0.dayKey != today || $0.completed }
        let window = Array(eligible.suffix(windowDays))
        guard window.count >= minimumHistoryDays else {
            return Result(score: nil, historyDays: window.count)
        }
        var weighted = 0.0
        var weightSum = 0.0
        let count = window.count
        for (index, result) in window.enumerated() {
            let age = Double(count - 1 - index)
            let weight = pow(0.5, age / halfLifeDays)
            let credit = result.completed ? 1.0 : min(result.ratio, 0.99) * 0.5
            weighted += weight * credit
            weightSum += weight
        }
        let score = weightSum > 0 ? Int((100 * weighted / weightSum).rounded()) : 0
        return Result(score: min(max(score, 0), 100), historyDays: count)
    }
}
