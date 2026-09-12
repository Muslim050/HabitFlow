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

    private var habits: [Habit] { allHabits.filter { $0.archivedAt == nil } }

    @AppStorage("activityRange", store: AppSettings.store) private var storedRange = ActivityRange.week.rawValue

    enum ActivityRange: String, CaseIterable, Identifiable {
        case week, fortnight, halfYear
        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .week: return "Week"
            case .fortnight: return "2 weeks"
            case .halfYear: return "6 months"
            }
        }

        var days: Int? {
            switch self {
            case .week: return 7
            case .fortnight: return 14
            case .halfYear: return nil
            }
        }
    }

    private var range: ActivityRange { ActivityRange(rawValue: storedRange) ?? .week }

    private let gap: CGFloat = 4
    private let labelWidth: CGFloat = 104

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
            } else if let days = range.days {
                matrix(days: days)
            } else {
                contributionGrid
            }
        }
    }

    // MARK: Week / fortnight

    private func matrix(days: Int) -> some View {
        GeometryReader { geo in
            let cell = HabitMatrixView.cellThatFits(width: geo.size.width, days: days,
                                                    gap: gap, labelWidth: labelWidth)
            HabitMatrixView(
                matrix: HabitMatrix.build(habits: habits, logs: logs, calendar: env.settings.dayCalendar,
                                          today: env.currentDayKey, days: days),
                calendar: env.settings.dayCalendar, today: env.currentDayKey,
                cell: cell, gap: gap, labelWidth: labelWidth, maxRows: 12
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: matrixHeight(days: days))
    }

    /// The grid is laid out by hand, so its height has to be stated rather than measured.
    private func matrixHeight(days: Int) -> CGFloat {
        let cell = HabitMatrixView.cellThatFits(width: rowWidth, days: days, gap: gap, labelWidth: labelWidth)
        let rowCount = min(habits.count, 12)
        let headerHeight = max(7, cell * 0.4) + gap + 2
        return headerHeight + CGFloat(rowCount) * cell + CGFloat(max(0, rowCount - 1)) * (gap + 2)
    }

    /// The card's content width on a phone: screen minus the list's own insets.
    private var rowWidth: CGFloat {
        #if os(iOS)
        UIScreen.main.bounds.width - 2 * 20 - 2 * 16
        #else
        320
        #endif
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
                           today: env.currentDayKey, weeks: weeks)
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
