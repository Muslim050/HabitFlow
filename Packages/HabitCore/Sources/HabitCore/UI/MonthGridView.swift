import SwiftUI

/// A month where each day is a stack of thin bars, one per habit, in that habit's colour.
///
/// Why stripes rather than one shaded square per day: with three habits a shaded square can say
/// "two of three" but never *which* two, and "which" is the whole question when you are looking
/// for the one that keeps slipping. The legend underneath ties colour to name, so the grid needs
/// no labels of its own and stays small.
public struct MonthGridView: View {
    public var grid: MonthGrid
    public var onSelect: ((DayKey) -> Void)?

    /// Day cells are square-ish; the stripes divide their height.
    /// Tall enough for the date plus one stripe per habit.
    public var cellHeight: CGFloat
    public var spacing: CGFloat
    /// Off in a widget: there is no room, and the shape of the month is the point there.
    public var showsDayNumbers: Bool
    /// Off when something above already names the habits in the same row order.
    public var showsLegend: Bool

    public init(grid: MonthGrid, cellHeight: CGFloat = 44, spacing: CGFloat = 4,
                showsDayNumbers: Bool = true, showsLegend: Bool = true,
                onSelect: ((DayKey) -> Void)? = nil) {
        self.grid = grid
        self.cellHeight = cellHeight
        self.spacing = spacing
        self.showsDayNumbers = showsDayNumbers
        self.showsLegend = showsLegend
        self.onSelect = onSelect
    }

    private var stripes: Int { min(grid.lanes.count, MonthGrid.maxLegibleLanes) }

    public var body: some View {
        VStack(alignment: .leading, spacing: spacing + 2) {
            header
            ForEach(0..<max(grid.weeks, 0), id: \.self) { week in
                HStack(spacing: spacing) {
                    ForEach(grid.days[(week * 7)..<min((week + 1) * 7, grid.days.count)]) { day in
                        cell(day)
                    }
                }
            }
            if showsLegend { legend }
        }
    }

    private var header: some View {
        HStack(spacing: spacing) {
            ForEach(Array(grid.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func cell(_ day: MonthGrid.Day) -> some View {
        let content = VStack(spacing: 2) {
            if showsDayNumbers {
                Text(verbatim: "\(day.dayOfMonth)")
                    .font(.system(size: 9, weight: day.isToday ? .bold : .regular))
                    .foregroundStyle(day.isToday ? Color.primary : Color.secondary)
            }
            VStack(spacing: 1.5) {
                ForEach(0..<stripes, id: \.self) { lane in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(colour(day.states[lane], lane: lane))
                }
            }
        }
        .padding(3)
        .frame(maxWidth: .infinity)
        .frame(height: cellHeight)
        .background(day.isToday ? Color.primary.opacity(0.07) : Color.secondary.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            if day.isToday {
                RoundedRectangle(cornerRadius: 7).stroke(Color.primary.opacity(0.45), lineWidth: 1.2)
            }
        }
        .opacity(day.isOutsideMonth ? 0.25 : 1)
        .accessibilityLabel(label(for: day))

        if let onSelect, !day.isOutsideMonth {
            Button { onSelect(day.key) } label: { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }

    private func colour(_ state: MatrixState, lane: Int) -> Color {
        let base = Color(hex: grid.lanes[lane].colorHex)
        switch state {
        case .done: return base
        case .partial(let ratio): return base.opacity(0.25 + 0.45 * min(max(ratio, 0), 1))
        case .missed: return Color.secondary.opacity(0.22)
        case .off: return Color.secondary.opacity(0.10)
        case .upcoming: return Color.secondary.opacity(0.05)
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(grid.lanes.prefix(MonthGrid.maxLegibleLanes).enumerated()), id: \.element.id) { index, lane in
                HStack(spacing: 8) {
                    // A miniature of the day cell with only this lane lit. Two habits can be given
                    // the same colour, and then a plain swatch identifies nothing — the row does.
                    swatch(for: index)
                    Text(lane.name).font(.caption)
                    Spacer()
                    Text(verbatim: "\(lane.done)/\(lane.required)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if grid.lanes.count > MonthGrid.maxLegibleLanes {
                Text("\(grid.lanes.count - MonthGrid.maxLegibleLanes) more not shown")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.top, 2)
    }

    /// The cell as it would look if only `lane` were kept, so the legend reads as a key to rows.
    private func swatch(for lane: Int) -> some View {
        VStack(spacing: 1) {
            ForEach(0..<stripes, id: \.self) { row in
                RoundedRectangle(cornerRadius: 1)
                    .fill(row == lane ? Color(hex: grid.lanes[lane].colorHex) : Color.secondary.opacity(0.14))
                    .frame(height: 3)
            }
        }
        .frame(width: 20)
    }

    private func label(for day: MonthGrid.Day) -> Text {
        guard !day.isOutsideMonth else { return Text(verbatim: "") }
        let kept = zip(grid.lanes, day.states).filter { $0.1 == .done }.map(\.0.name)
        guard !kept.isEmpty else { return Text("\(day.dayOfMonth): nothing") }
        return Text("\(day.dayOfMonth): \(kept.joined(separator: ", "))")
    }
}
