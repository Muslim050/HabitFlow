import SwiftData
import SwiftUI
import HabitCore

/// The all-habits activity grid plus the three numbers that make it readable.
/// The grid is fitted to the available width rather than scrolled: a horizontal scroller
/// carried the weekday labels off screen and hid the fact that the grid ends today.
struct ActivitySection: View {
    @Environment(AppEnvironment.self) private var env
    @Query(filter: #Predicate<Habit> { $0.archivedAt == nil }) private var habits: [Habit]
    @Query private var logs: [DailyLog]

    private let cell: CGFloat = 13
    private let gap: CGFloat = 3
    /// Width taken by the fixed weekday column plus its gap.
    private let gutter: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GeometryReader { geo in
                let weeks = min(26, ActivityGridView.weeksThatFit(width: geo.size.width - gutter, cell: cell, gap: gap))
                let summary = ActivityGrid.build(habits: habits, logs: logs,
                                                 calendar: env.settings.dayCalendar,
                                                 today: env.currentDayKey, weeks: weeks)
                ActivityGridView(summary: summary, calendar: env.settings.dayCalendar,
                                 today: env.currentDayKey, cell: cell, gap: gap,
                                 showsMonths: true, showsWeekdays: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 7 * cell + 6 * gap + 16)

            let summary = ActivityGrid.build(habits: habits, logs: logs, calendar: env.settings.dayCalendar,
                                             today: env.currentDayKey, weeks: 26)
            HStack(spacing: 0) {
                stat("\(summary.activeDays)", "Active days")
                divider
                stat("\(summary.currentStreak)", "Current streak")
                divider
                stat("\(summary.bestStreak)", "Best streak")
            }
        }
    }

    private func stat(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.bold().monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var divider: some View {
        Rectangle().fill(Color.secondary.opacity(0.2)).frame(width: 1, height: 26)
    }
}
