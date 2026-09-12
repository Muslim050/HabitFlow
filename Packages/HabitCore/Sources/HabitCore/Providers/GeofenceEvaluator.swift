import Foundation

/// Pure dwell-time evaluation shared by the location provider and tests.
public enum GeofenceEvaluator {
    /// Longest single stay inside `window`, in minutes. Open visits are measured up to `now`.
    public static func longestStayMinutes(visits: [DateInterval], window: DateInterval) -> Double {
        IntervalMath.longestDuration(of: visits, clippedTo: window) / 60
    }

    public static func snapshot(rule: HabitRule, visits: [DateInterval], window: DateInterval, now: Date) -> ProgressSnapshot {
        guard case .geofence(_, _, _, let minDwell, let placeName) = rule else {
            return ProgressSnapshot(value: 0, target: 1, isSatisfied: false, observedAt: now)
        }
        // Whole minutes only, so the displayed value never reads "1 / 1" while the rule is still unmet.
        let minutes = floor(longestStayMinutes(visits: visits, window: window))
        let detail = visits.isEmpty
            ? String(localized: "No visit to \(placeName) yet", bundle: .module)
            : String(localized: "\(Int(minutes)) min at \(placeName)", bundle: .module)
        return ProgressSnapshot(value: minutes, target: minDwell, observedAt: now, detail: detail)
    }
}
