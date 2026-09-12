import SwiftUI

/// The all-habits contribution grid: a column per week, a row per weekday, newest on the right.
/// Lives in the package so the app and the widget draw exactly the same thing.
public struct ActivityGridView: View {
    public var summary: ActivitySummary
    public var calendar: DayCalendar
    public var today: DayKey
    public var color: Color
    public var cell: CGFloat
    public var gap: CGFloat
    public var showsMonths: Bool
    public var showsWeekdays: Bool

    public init(summary: ActivitySummary, calendar: DayCalendar, today: DayKey,
                color: Color = .accentColor, cell: CGFloat = 13, gap: CGFloat = 3,
                showsMonths: Bool = false, showsWeekdays: Bool = false) {
        self.summary = summary
        self.calendar = calendar
        self.today = today
        self.color = color
        self.cell = cell
        self.gap = gap
        self.showsMonths = showsMonths
        self.showsWeekdays = showsWeekdays
    }

    private var columns: Int { summary.days.count / 7 }
    private var pitch: CGFloat { cell + gap }

    public var body: some View {
        HStack(alignment: .top, spacing: gap + 2) {
            if showsWeekdays { weekdayColumn }
            VStack(alignment: .leading, spacing: gap) {
                if showsMonths { monthStrip }
                grid
            }
        }
    }

    private var grid: some View {
        HStack(alignment: .top, spacing: gap) {
            ForEach(0..<columns, id: \.self) { column in
                VStack(spacing: gap) {
                    ForEach(0..<7, id: \.self) { row in
                        cellView(summary.days[column * 7 + row])
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Activity for \(columns) weeks: \(summary.activeDays) active days"))
    }

    @ViewBuilder
    private func cellView(_ day: ActivityDay?) -> some View {
        let isToday = day?.dayKey == today
        RoundedRectangle(cornerRadius: cell * 0.2, style: .continuous)
            .fill(fill(day))
            .frame(width: cell, height: cell)
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: cell * 0.2, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.55), lineWidth: 1)
                }
            }
    }

    private func fill(_ day: ActivityDay?) -> Color {
        guard let day else { return .clear }
        // An off day is not a miss, and must not read like one.
        if day.isOffDay { return Color.secondary.opacity(0.06) }
        switch day.level {
        case 0: return Color.secondary.opacity(0.14)
        case 1: return color.opacity(0.3)
        case 2: return color.opacity(0.5)
        case 3: return color.opacity(0.72)
        default: return color
        }
    }

    private var monthStrip: some View {
        let labels = ActivityGrid.monthLabels(days: summary.days, calendar: calendar)
        return HStack(alignment: .bottom, spacing: gap) {
            ForEach(0..<columns, id: \.self) { column in
                Text(labels[column] ?? "")
                    .font(.system(size: max(7, cell * 0.62)))
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .frame(width: cell, alignment: .leading)
            }
        }
        .frame(height: max(9, cell * 0.8), alignment: .bottom)
        .clipped()
    }

    /// Mon / Wed / Fri, the three rows a reader needs to orient the others.
    private var weekdayColumn: some View {
        let symbols = calendar.calendar.veryShortStandaloneWeekdaySymbols
        return VStack(spacing: gap) {
            if showsMonths { Color.clear.frame(height: max(9, cell * 0.8)) }
            ForEach(0..<7, id: \.self) { row in
                Text([1, 3, 5].contains(row) ? symbols[row] : " ")
                    .font(.system(size: max(7, cell * 0.62)))
                    .foregroundStyle(.secondary)
                    .frame(height: cell)
            }
        }
    }
}

/// How many whole weeks fit in a given width at this cell size.
public extension ActivityGridView {
    static func weeksThatFit(width: CGFloat, cell: CGFloat = 13, gap: CGFloat = 3) -> Int {
        max(1, Int((width + gap) / (cell + gap)))
    }
}
