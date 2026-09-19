import SwiftUI
import HabitCore

/// GitHub-style grid: one column per week, one row per weekday, newest week on the right.
struct HeatmapView: View {
    let results: [DayResult]
    let color: Color
    let weeks: Int
    let calendar: DayCalendar
    let today: DayKey
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
        var days: [DayResult?] = calendar.keys(from: start, to: today).map { byKey[$0] ?? DayResult(dayKey: $0, scheduled: false, completed: false) }
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
        RoundedRectangle(cornerRadius: 2.5)
            .fill(fill(result))
            .frame(width: 13, height: 13)
            .overlay {
                if result?.dayKey == today {
                    RoundedRectangle(cornerRadius: 2.5).stroke(Color.primary.opacity(0.6), lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
    }

    private func label(for result: DayResult) -> String {
        let state = result.completed
            ? String(localized: "done")
            : (result.scheduled ? String(localized: "not done") : String(localized: "not scheduled"))
        return "\(result.dayKey.raw), \(state)"
    }

    private func fill(_ result: DayResult?) -> Color {
        guard let result else { return .clear }
        if !result.scheduled { return Color.secondary.opacity(0.08) }
        if result.completed { return color }
        if result.ratio > 0 { return color.opacity(0.2 + 0.5 * result.ratio) }
        return Color.secondary.opacity(0.2)
    }
}
