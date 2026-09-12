import Foundation

public enum EvaluationReason: String, Sendable {
    case foreground
    case timer
    case healthKitDelivery
    case locationEvent
    case backgroundRefresh
    case manualRefresh
    case dayRollover
    case habitChanged
}
