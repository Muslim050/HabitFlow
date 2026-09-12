import SwiftUI
import WidgetKit
import HabitCore

struct ActivityEntry: TimelineEntry {
    let date: Date
    let summary: ActivitySummary
    let calendar: DayCalendar
    let today: DayKey
    let hasHabits: Bool

    static var placeholder: ActivityEntry {
        let calendar = AppSettings.shared.dayCalendar
        return ActivityEntry(date: Date(), summary: .empty, calendar: calendar,
                             today: calendar.today(), hasHabits: false)
    }
}

struct ActivityProvider: TimelineProvider {
    /// 19 columns is what fits a medium widget at the app's own cell size.
    static let weeks = 19

    func placeholder(in context: Context) -> ActivityEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (ActivityEntry) -> Void) {
        Task { @MainActor in completion(Self.load()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ActivityEntry>) -> Void) {
        Task { @MainActor in
            let entry = Self.load()
            // The grid only changes on a completion or at the day boundary; a slow cadence is enough.
            let refresh = Calendar.current.date(byAdding: .hour, value: 1, to: entry.date) ?? entry.date.addingTimeInterval(3600)
            completion(Timeline(entries: [entry], policy: .after(refresh)))
        }
    }

    @MainActor
    static func load() -> ActivityEntry {
        let settings = AppSettings.shared
        let calendar = settings.dayCalendar
        let today = calendar.today()
        guard let container = try? ModelContainerFactory.shared() else { return .placeholder }
        let repository = SwiftDataHabitRepository(container: container)
        let habits = (try? repository.activeHabits()) ?? []
        let from = calendar.key(byAdding: -(weeks * 7 + 7), to: today)
        let logs = (try? repository.logs(from: from, to: today)) ?? []
        return ActivityEntry(
            date: Date(),
            summary: ActivityGrid.build(habits: habits, logs: logs, calendar: calendar, today: today, weeks: weeks),
            calendar: calendar,
            today: today,
            hasHabits: !habits.isEmpty
        )
    }
}

struct ActivityWidget: Widget {
    let kind = "ActivityGrid"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ActivityProvider()) { entry in
            ActivityWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Activity")
        .description("Every day across all habits, like a contribution grid.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct ActivityWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ActivityEntry

    private var isLarge: Bool { family == .systemLarge }

    // A medium widget has about 306x126 pt of content room. A 13/3 grid is 109 tall and
    // leaves nothing for the numbers, so medium uses a tighter cell and a one-line header.
    private var cell: CGFloat { isLarge ? 13 : 12 }
    private var gap: CGFloat { isLarge ? 3 : 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: isLarge ? 12 : 8) {
            header
            if entry.hasHabits {
                ActivityGridView(
                    summary: entry.summary, calendar: entry.calendar, today: entry.today,
                    cell: cell, gap: gap,
                    // Weekday letters would be 8 pt of secondary ink on a translucent
                    // widget background: present but unreadable. The app screen keeps them.
                    showsMonths: isLarge, showsWeekdays: false
                )
                if isLarge {
                    legend
                    Spacer(minLength: 0)
                    todayLine
                }
            } else {
                Text("Add a habit in HabitFlow")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .widgetURL(URL(string: "habitflow://today"))
    }

    @ViewBuilder
    private var header: some View {
        if isLarge {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                stat("\(entry.summary.activeDays)", "Active days")
                stat("\(entry.summary.currentStreak)", "Current streak")
                stat("\(entry.summary.bestStreak)", "Best streak")
                Spacer(minLength: 0)
            }
        } else {
            HStack(spacing: 6) {
                Text("\(entry.summary.activeDays)").font(.subheadline.bold().monospacedDigit())
                Text("Active days").font(.system(size: 10)).foregroundStyle(.secondary)
                Text(verbatim: "·").foregroundStyle(.secondary)
                Text("\(entry.summary.currentStreak)").font(.subheadline.bold().monospacedDigit())
                Text("Current streak").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.85)
        }
    }

    private func stat(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.headline.monospacedDigit())
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    /// Grounds the grid in the present: the rightmost cell is this.
    @ViewBuilder
    private var todayLine: some View {
        if let today = entry.summary.days.compactMap({ $0 }).last {
            HStack(spacing: 6) {
                Text("Today").font(.system(size: 11, weight: .semibold))
                if today.scheduled > 0 {
                    Text(verbatim: "\(today.completed) / \(today.scheduled)")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Text("Day off").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// Says what the shades mean; without it a half-filled cell is a guess.
    private var legend: some View {
        HStack(spacing: 5) {
            Text("Less").font(.system(size: 9)).foregroundStyle(.secondary)
            ForEach(0..<5, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(level == 0 ? Color.secondary.opacity(0.14) : Color.accentColor.opacity([0, 0.3, 0.5, 0.72, 1][level]))
                    .frame(width: 11, height: 11)
            }
            Text("All done").font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }
}

#Preview("Medium", as: .systemMedium) {
    ActivityWidget()
} timeline: {
    ActivityEntry.placeholder
}
