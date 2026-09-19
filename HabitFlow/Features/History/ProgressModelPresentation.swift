import SwiftUI
import HabitCore

extension ProgressModel {
    var displayName: String {
        switch self {
        case .habitScore: return String(localized: "Strength")
        case .consecutiveStreak: return String(localized: "Streak")
        case .completionRate: return String(localized: "Completion rate")
        case .totalCompletions: return String(localized: "Total")
        }
    }

    var explanation: LocalizedStringKey {
        switch self {
        case .habitScore:
            return "Rises with repetition and dips on a miss, never back to zero. Slow in both directions."
        case .consecutiveStreak:
            return "Kept periods in a row. Freezes hold it together; run out of them and it restarts."
        case .completionRate:
            return "Share of recent periods you kept."
        case .totalCompletions:
            return "Everything you have ever kept, and it only goes up."
        }
    }
}

/// The one number a habit leads with, chosen by its progress model. The detail screen shows the
/// others below it, so switching models changes the emphasis rather than hiding anything.
struct ProgressHeadline {
    var title: String
    var value: String
    var detail: String?

    init(stats: HabitStats, freezesPerMonth: Int, today: DayKey) {
        title = stats.progressModel.displayName
        switch stats.progressModel {
        case .habitScore:
            value = "\(stats.habitScore) / 100"
            detail = String(localized: "Grows with repetition")
        case .consecutiveStreak:
            value = SchedulePeriodText.length(stats.currentStreak.length, stats.period)
            let left = StreakCalculator.freezesLeft(in: today, streak: stats.currentStreak,
                                                    freezesPerMonth: freezesPerMonth)
            detail = String(localized: "\(left) freezes left this month")
        case .completionRate:
            value = stats.completionRate.formatted(.percent.precision(.fractionLength(0)))
            detail = SchedulePeriodText.window(ConsistencyScore.window(for: stats.period).span, stats.period)
        case .totalCompletions:
            value = "\(stats.totalCompletions)"
            detail = nil
        }
    }
}
