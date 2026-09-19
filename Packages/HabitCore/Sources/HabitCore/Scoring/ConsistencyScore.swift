import Foundation

/// A 0…100 recency-weighted completion index that replaces streak anxiety.
public enum ConsistencyScore {
    /// Window and warm-up length, in obligations. A month-quota habit produces one obligation a
    /// month, so counting 30 of them would reach back years; each period gets its own span.
    public struct Window: Sendable, Equatable {
        public var span: Int
        public var minimum: Int
    }

    public static func window(for period: SchedulePeriod) -> Window {
        switch period {
        case .day: return Window(span: 30, minimum: 7)
        case .week: return Window(span: 8, minimum: 3)
        case .month: return Window(span: 6, minimum: 2)
        }
    }

    public struct Result: Sendable, Equatable {
        public var score: Int?
        /// Obligations available, in the schedule's own period.
        public var history: Int
        public var minimum: Int
        public var period: SchedulePeriod
        public var isWarmingUp: Bool { score == nil }
    }

    /// `obligations` ascending. A still-running obligation is included only once fulfilled, so an
    /// unfinished week never drags the score down mid-week. Too little history ⇒ `score == nil`.
    public static func compute(_ obligations: [ObligationResult], halfLife: Double? = nil) -> Result {
        let period = obligations.last?.period ?? .day
        let bounds = window(for: period)
        let eligible = obligations.filter { !$0.isOpen || $0.fulfilled }
        let recent = Array(eligible.suffix(bounds.span))
        guard recent.count >= bounds.minimum else {
            return Result(score: nil, history: recent.count, minimum: bounds.minimum, period: period)
        }
        // Half the window, so the newest obligation weighs about twice the oldest kept one.
        let decay = halfLife ?? Double(bounds.span) / 2
        var weighted = 0.0
        var weightSum = 0.0
        let count = recent.count
        for (index, obligation) in recent.enumerated() {
            let age = Double(count - 1 - index)
            let weight = pow(0.5, age / decay)
            weighted += weight * obligation.credit
            weightSum += weight
        }
        let score = weightSum > 0 ? Int((100 * weighted / weightSum).rounded()) : 0
        return Result(score: min(max(score, 0), 100), history: count, minimum: bounds.minimum, period: period)
    }
}
