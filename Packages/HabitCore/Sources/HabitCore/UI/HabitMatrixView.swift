import SwiftUI

/// Habits down the side in their own colours, days across the top. Shared by the app screen
/// and the widget so both read the same way.
public struct HabitMatrixView: View {
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

    public init(matrix: HabitMatrix, calendar: DayCalendar, today: DayKey,
                cell: CGFloat = 26, gap: CGFloat = 4, labelWidth: CGFloat = 104,
                showsDayHeader: Bool = true, showsCounts: Bool = true, maxRows: Int = 8) {
        self.matrix = matrix
        self.calendar = calendar
        self.today = today
        self.cell = cell
        self.gap = gap
        self.labelWidth = labelWidth
        self.showsDayHeader = showsDayHeader
        self.showsCounts = showsCounts
        self.maxRows = maxRows
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
                    .frame(width: cell)
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
                cellView(state: state, color: color, isToday: matrix.days.indices.contains(index) && matrix.days[index] == today)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(row.name): \(row.doneCount) of \(row.scheduledCount)"))
    }

    private func cellView(state: MatrixState, color: Color, isToday: Bool) -> some View {
        RoundedRectangle(cornerRadius: cell * 0.28, style: .continuous)
            .fill(fill(state, color: color))
            .frame(width: cell, height: cell)
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
        }
    }

    private func weekdayLetter(_ day: DayKey) -> String {
        let symbols = calendar.calendar.veryShortStandaloneWeekdaySymbols
        let index = calendar.weekday(for: day) - 1
        return symbols.indices.contains(index) ? symbols[index] : ""
    }
}

public extension HabitMatrixView {
    /// Cell size that makes `days` columns fit the width left after the label column.
    static func cellThatFits(width: CGFloat, days: Int, gap: CGFloat, labelWidth: CGFloat) -> CGFloat {
        guard days > 0 else { return 0 }
        let free = width - labelWidth - gap * CGFloat(days)
        return max(6, (free / CGFloat(days)).rounded(.down))
    }
}
