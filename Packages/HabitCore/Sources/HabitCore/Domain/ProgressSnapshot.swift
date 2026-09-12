import Foundation

/// What a provider observed for one habit in one day window.
public struct ProgressSnapshot: Sendable, Equatable {
    public var value: Double
    public var target: Double
    public var isSatisfied: Bool
    public var observedAt: Date
    public var detail: String?

    public init(value: Double, target: Double, isSatisfied: Bool? = nil, observedAt: Date, detail: String? = nil) {
        self.value = value
        self.target = target
        self.isSatisfied = isSatisfied ?? (target > 0 ? value >= target : value > 0)
        self.observedAt = observedAt
        self.detail = detail
    }

    public var ratio: Double {
        guard target > 0 else { return isSatisfied ? 1 : 0 }
        return min(max(value / target, 0), 1)
    }
}
