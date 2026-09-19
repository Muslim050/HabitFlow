import SwiftUI

/// Habits down the side in their own colours, days across the top. Shared by the app screen
/// and the widget so both read the same way.
public struct HabitMatrixView<TodayOverlay: View>: View {
    public var matrix: HabitMatrix
    public var calendar: DayCalendar
    public var today: DayKey
    public var cell: CGFloat
    public var gap: CGFloat
    public var labelWidth: CGFloat
    public var showsDayHeader: Bool
    public var showsCounts: Bool
    /// Rows beyond this are folded into a "+N more" line.
    public var maxRows: Int
    /// Today's column is wider: it is the one a person acts on.
    public var todayCell: CGFloat
    /// Placed over today's cell. A widget puts an intent button here; the app passes nothing.
    private let todayOverlay: (HabitMatrix.Row) -> TodayOverlay

    public init(matrix: HabitMatrix, calendar: DayCalendar, today: DayKey,
                cell: CGFloat = 26, gap: CGFloat = 4, labelWidth: CGFloat = 104,
                showsDayHeader: Bool = true, showsCounts: Bool = true, maxRows: Int = 8,
                todayCell: CGFloat? = nil,
                @ViewBuilder todayOverlay: @escaping (HabitMatrix.Row) -> TodayOverlay) {
        self.matrix = matrix
        self.calendar = calendar
        self.today = today
        self.cell = cell
        self.gap = gap
        self.labelWidth = labelWidth
        self.showsDayHeader = showsDayHeader
        self.showsCounts = showsCounts
        self.maxRows = maxRows
        self.todayCell = todayCell ?? cell
        self.todayOverlay = todayOverlay
    }

    private var visibleRows: [HabitMatrix.Row] { Array(matrix.rows.prefix(maxRows)) }
    private var hiddenCount: Int { max(0, matrix.rows.count - maxRows) }

    public var body: some View {
        VStack(alignment: .leading, spacing: gap + 2) {
            if showsDayHeader { dayHeader }
            ForEach(visibleRows) { row in
                habitRow(row)
            }
            if hiddenCount > 0 {
                Text("+\(hiddenCount) more")
                    .font(.system(size: max(8, cell * 0.38)))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 2)
            }
        }
    }

    private var dayHeader: some View {
        HStack(spacing: gap) {
            Color.clear.frame(width: labelWidth, height: 1)
            ForEach(matrix.days, id: \.raw) { day in
                Text(weekdayLetter(day))
                    .font(.system(size: max(7, cell * 0.4), weight: day == today ? .bold : .regular))
                    .foregroundStyle(day == today ? Color.primary : Color.secondary)
                    .frame(width: day == today ? todayCell : cell)
            }
        }
    }

    private func habitRow(_ row: HabitMatrix.Row) -> some View {
        let color = Color(hex: row.colorHex)
        return HStack(spacing: gap) {
            HStack(spacing: 5) {
                Text(row.emoji).font(.system(size: max(10, cell * 0.5)))
                VStack(alignment: .leading, spacing: 0) {
                    Text(row.name)
                        .font(.system(size: max(9, cell * 0.42), weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if showsCounts {
                        Text(verbatim: "\(row.doneCount)/\(row.scheduledCount)")
                            .font(.system(size: max(7, cell * 0.34)).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: labelWidth, alignment: .leading)

            ForEach(Array(row.states.enumerated()), id: \.offset) { index, state in
                let isToday = matrix.days.indices.contains(index) && matrix.days[index] == today
                cellView(state: state, color: color, isToday: isToday)
                    .overlay { if isToday { todayOverlay(row) } }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(row.name): \(row.doneCount) of \(row.scheduledCount)"))
    }

    private func cellView(state: MatrixState, color: Color, isToday: Bool) -> some View {
        let width = isToday ? todayCell : cell
        return RoundedRectangle(cornerRadius: cell * 0.28, style: .continuous)
            .fill(fill(state, color: color))
            .frame(width: width, height: cell)
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: cell * 0.28, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.45), lineWidth: 1)
                }
            }
            .overlay {
                // A tick inside a full cell survives being printed, screenshotted, or read
                // by someone who cannot separate the colour from the miss grey.
                if case .done = state, cell >= 20 {
                    Image(systemName: "checkmark")
                        .font(.system(size: cell * 0.42, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
    }

    private func fill(_ state: MatrixState, color: Color) -> Color {
        switch state {
        case .done: return color
        case .partial(let ratio): return color.opacity(0.25 + 0.45 * min(max(ratio, 0), 1))
        case .missed: return Color.secondary.opacity(0.16)
        case .off: return Color.secondary.opacity(0.06)
        // Lighter than an off day: nothing is being said about it yet.
        case .upcoming: return Color.secondary.opacity(0.03)
        }
    }

    private func weekdayLetter(_ day: DayKey) -> String {
        let symbols = calendar.calendar.veryShortStandaloneWeekdaySymbols
        let index = calendar.weekday(for: day) - 1
        return symbols.indices.contains(index) ? symbols[index] : ""
    }
}

public extension HabitMatrixView where TodayOverlay == EmptyView {
    /// Read-only matrix: no affordance on today.
    init(matrix: HabitMatrix, calendar: DayCalendar, today: DayKey,
         cell: CGFloat = 26, gap: CGFloat = 4, labelWidth: CGFloat = 104,
         showsDayHeader: Bool = true, showsCounts: Bool = true, maxRows: Int = 8,
         todayCell: CGFloat? = nil) {
        self.init(matrix: matrix, calendar: calendar, today: today, cell: cell, gap: gap,
                  labelWidth: labelWidth, showsDayHeader: showsDayHeader, showsCounts: showsCounts,
                  maxRows: maxRows, todayCell: todayCell) { _ in EmptyView() }
    }
}

public enum HabitMatrixMetrics {
    /// Cell size that makes `days` columns fit the width left after the label column,
    /// when today's column is `todayExtra` points wider than the rest.
    public static func cellThatFits(width: CGFloat, days: Int, gap: CGFloat,
                                    labelWidth: CGFloat, todayExtra: CGFloat = 0) -> CGFloat {
        guard days > 0 else { return 0 }
        let free = width - labelWidth - gap * CGFloat(days) - todayExtra
        return max(6, (free / CGFloat(days)).rounded(.down))
    }
}
