import SwiftData
import SwiftUI
import HabitCore

/// Activity across all habits. A week or a fortnight shows habits as their own coloured rows,
/// which is the only way to see which habit did what; the half-year view keeps the
/// single-series contribution grid for the long view.
struct ActivitySection: View {
    @Environment(AppEnvironment.self) private var env
    // A predicate and a sort together in the attribute form sent the type checker over its
    // budget; sorting in the query and filtering here costs nothing at these row counts.
    @Query(sort: [SortDescriptor(\Habit.sortOrder), SortDescriptor(\Habit.createdAt)])
    private var allHabits: [Habit]
    @Query private var logs: [DailyLog]
    @Query private var pauses: [HabitPause]

    private var habits: [Habit] { allHabits.filter { $0.archivedAt == nil } }

    @AppStorage("activityRange", store: AppSettings.store) private var storedRange = ActivityRange.week.rawValue

    enum ActivityRange: String, CaseIterable, Identifiable {
        case week, fortnight, month, halfYear
        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .week: return "Week"
            case .fortnight: return "2 weeks"
            case .month: return "Month"
            case .halfYear: return "6 months"
            }
        }

        /// Whole calendar weeks, ending with the one today falls in.
        var weeks: Int? {
            switch self {
            case .week: return 1
            case .fortnight: return 2
            case .month, .halfYear: return nil
            }
        }
    }

    private var range: ActivityRange { ActivityRange(rawValue: storedRange) ?? .week }

    /// Fixed metrics per range. Deriving the cell from a measured width meant the
    /// section's own height was computed from an estimate, and the last habit was clipped.
    private var metrics: (cell: CGFloat, gap: CGFloat, label: CGFloat) {
        range == .fortnight ? (12, 3, 96) : (26, 4, 104)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Range", selection: $storedRange) {
                ForEach(ActivityRange.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)

            if habits.isEmpty {
                Text("Add a habit to see activity here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if let weeks = range.weeks {
                matrix(weeks: weeks)
            } else if range == .month {
                monthGrid
            } else {
                contributionGrid
            }
        }
    }

    // MARK: Week / fortnight

    private func matrix(weeks: Int) -> some View {
        let m = metrics
        return VStack(alignment: .leading, spacing: 10) {
            matrixView(weeks: weeks, metrics: m)
            Text("Each habit in its own colour. A day with nothing scheduled is an off day, not a miss.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func matrixView(weeks: Int, metrics m: (cell: CGFloat, gap: CGFloat, label: CGFloat)) -> some View {
        HabitMatrixView(
            matrix: HabitMatrix.build(habits: habits, logs: logs, calendar: env.settings.dayCalendar,
                                      today: env.currentDayKey, weeks: weeks, pauses: pauses),
            calendar: env.settings.dayCalendar, today: env.currentDayKey,
            cell: m.cell, gap: m.gap, labelWidth: m.label, maxRows: 12
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Month

    private var monthGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonthGridView(
                grid: MonthGrid.build(habits: habits, logs: logs, calendar: env.settings.dayCalendar,
                                      today: env.currentDayKey, month: env.currentDayKey, pauses: pauses)
            )
            Text("One stripe per habit, so a month shows which one slipped and not just how many.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Half year

    private var contributionGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            gridStrip
            summaryRow
            Text("One cell per day across all habits. Colour shows how much of the day closed.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var gridStrip: some View {
        GeometryReader { geo in
            let weeks = min(26, ActivityGridView.weeksThatFit(width: geo.size.width - 20, cell: 13, gap: 3))
            ActivityGridView(
                summary: summary(weeks: weeks),
                calendar: env.settings.dayCalendar, today: env.currentDayKey,
                cell: 13, gap: 3, showsMonths: true, showsWeekdays: true
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 7 * 13 + 6 * 3 + 16)
    }

    private var summaryRow: some View {
        let summary = summary(weeks: 26)
        return HStack(spacing: 0) {
            stat("\(summary.activeDays)", "Active days")
            divider
            stat("\(summary.currentStreak)", "Current streak")
            divider
            stat("\(summary.bestStreak)", "Best streak")
        }
    }

    private func summary(weeks: Int) -> ActivitySummary {
        ActivityGrid.build(habits: habits, logs: logs, calendar: env.settings.dayCalendar,
                           today: env.currentDayKey, weeks: weeks, pauses: pauses)
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
