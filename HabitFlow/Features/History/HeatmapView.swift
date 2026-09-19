import SwiftUI
import HabitCore

/// GitHub-style grid: one column per week, one row per weekday, newest week on the right.
struct HeatmapView: View {
    let results: [DayResult]
    let color: Color
    let weeks: Int
    let calendar: DayCalendar
    let today: DayKey
    /// Days a freeze covered. They are drawn apart from both done and missed, so a day the
    /// budget rescued never passes for a day that was actually kept.
    var frozen: Set<DayKey> = []
    /// Days inside this range are tappable; nil makes the grid read-only.
    var editable: ClosedRange<DayKey>? = nil
    var onSelect: ((DayKey) -> Void)? = nil

    private var cells: [DayResult?] {
        let byKey = Dictionary(results.map { ($0.dayKey, $0) }, uniquingKeysWith: { a, _ in a })
        // Grid ends on today; pad the last column so rows stay aligned to weekdays (Sunday = row 0).
        let todayWeekday = calendar.weekday(for: today)          // 1…7
        let trailingPad = 7 - todayWeekday
        let totalDays = weeks * 7 - trailingPad
        let start = calendar.key(byAdding: -(totalDays - 1), to: today)
        var days: [DayResult?] = calendar.keys(from: start, to: today).map { byKey[$0] ?? DayResult(dayKey: $0, obligation: .off, completed: false) }
        days.append(contentsOf: Array(repeating: nil, count: trailingPad))
        return days
    }

    var body: some View {
        let cells = cells
        let columns = cells.count / 7
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 3) {
                ForEach(0..<columns, id: \.self) { column in
                    VStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { row in
                            cell(cells[column * 7 + row])
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .defaultScrollAnchor(.trailing)
        .accessibilityLabel(Text("Completion history for the last \(weeks) weeks"))
        .accessibilityElement(children: onSelect == nil ? .ignore : .contain)
    }

    @ViewBuilder
    private func cell(_ result: DayResult?) -> some View {
        if let result, let onSelect, editable?.contains(result.dayKey) == true {
            Button { onSelect(result.dayKey) } label: { square(result) }
                .buttonStyle(.plain)
                .accessibilityLabel(label(for: result))
                .accessibilityHint("Edit this day")
        } else {
            square(result)
                .accessibilityHidden(result == nil)
                .accessibilityLabel(result.map(label(for:)) ?? "")
        }
    }

    private func square(_ result: DayResult?) -> some View {
        let isFrozen = result.map { frozen.contains($0.dayKey) && !$0.completed } ?? false
        return RoundedRectangle(cornerRadius: 2.5)
            .fill(fill(result))
            .frame(width: 13, height: 13)
            .overlay {
                if isFrozen {
                    // A dashed outline, not a fill: the day is held, not earned.
                    RoundedRectangle(cornerRadius: 2.5)
                        .strokeBorder(color.opacity(0.9), style: StrokeStyle(lineWidth: 1, dash: [2, 1.5]))
                }
                if result?.dayKey == today {
                    RoundedRectangle(cornerRadius: 2.5).stroke(Color.primary.opacity(0.6), lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
    }

    private func label(for result: DayResult) -> String {
        let state: String
        if result.completed {
            state = String(localized: "done")
        } else if frozen.contains(result.dayKey) {
            state = String(localized: "frozen")
        } else {
            switch result.obligation {
            case .required: state = String(localized: "not done")
            case .flexible: state = String(localized: "not required")
            case .paused: state = String(localized: "paused")
            case .off: state = String(localized: "not scheduled")
            }
        }
        return "\(result.dayKey.raw), \(state)"
    }

    private func fill(_ result: DayResult?) -> Color {
        guard let result else { return .clear }
        if result.completed { return color }
        // A paused day is not a gap in the habit, it is a gap on purpose — drawn a shade darker
        // than an off day so a holiday is visible as a block rather than as nothing.
        if result.obligation == .paused { return Color.secondary.opacity(0.14) }
        // Only a day the schedule named can look like a miss. On a quota schedule no single day
        // is owed, so an unused day reads as empty rather than as a failure.
        guard result.obligation == .required else { return Color.secondary.opacity(0.08) }
        if result.ratio > 0 { return color.opacity(0.2 + 0.5 * result.ratio) }
        return Color.secondary.opacity(0.2)
    }
}
