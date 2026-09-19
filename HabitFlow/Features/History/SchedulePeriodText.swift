import Foundation
import HabitCore

/// Streak lengths carry a unit that depends on the habit's schedule: a "three times a week"
/// habit keeps a run of weeks. Printing a bare number would read as days and be wrong.
enum SchedulePeriodText {
    static func length(_ count: Int, _ period: SchedulePeriod) -> String {
        switch period {
        case .day: return String(localized: "\(count) days")
        case .week: return String(localized: "\(count) weeks")
        case .month: return String(localized: "\(count) months")
        }
    }
}
