import Foundation

/// Why a hand edit of a particular day was refused.
public enum BackdateError: Error, Equatable, Sendable {
    /// Outside `AutoTrackingEngine.editableDayRange`, or before the habit was created.
    case dayNotEditable(DayKey)
    /// A measured value was written to a habit that has no measurement — a manual habit is a tick, not a number.
    case habitIsNotMeasured(UUID)
}
