import SwiftUI
import HabitCore

/// GitHub-style grid: one column per week, one row per weekday, newest week on the right.
struct HeatmapView: View {
    let results: [DayResult]
    let color: Color
    let weeks: Int
    let calendar: DayCalendar
    let today: DayKey

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
        .accessibilityLabel("Completion history for the last \(weeks) weeks")
    }

    @ViewBuilder
    private func cell(_ result: DayResult?) -> some View {
        RoundedRectangle(cornerRadius: 2.5)
            .fill(fill(result))
            .frame(width: 13, height: 13)
            .overlay {
                if result?.dayKey == today {
                    RoundedRectangle(cornerRadius: 2.5).stroke(Color.primary.opacity(0.6), lineWidth: 1)
                }
            }
    }

    private func fill(_ result: DayResult?) -> Color {
        guard let result else { return .clear }
        if !result.scheduled { return Color.secondary.opacity(0.08) }
        if result.completed { return color }
        if result.ratio > 0 { return color.opacity(0.2 + 0.5 * result.ratio) }
        return Color.secondary.opacity(0.2)
    }
}
