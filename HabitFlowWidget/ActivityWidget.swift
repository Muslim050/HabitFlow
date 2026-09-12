import AppIntents
import SwiftUI
import WidgetKit
import HabitCore

struct ActivityEntry: TimelineEntry {
    let date: Date
    let matrix: HabitMatrix
    let calendar: DayCalendar
    let today: DayKey
    /// Presets that are not already in the store, so the widget never offers a duplicate.
    let availablePresets: [HabitPreset]

    var hasHabits: Bool { !matrix.rows.isEmpty }

    static var placeholder: ActivityEntry {
        let calendar = AppSettings.shared.dayCalendar
        return ActivityEntry(date: Date(), matrix: .empty, calendar: calendar,
                             today: calendar.today(), availablePresets: HabitPreset.allCases)
    }
}

struct ActivityProvider: TimelineProvider {
    /// A week reads at widget size; two weeks would halve the cells.
    static let days = 7

    func placeholder(in context: Context) -> ActivityEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (ActivityEntry) -> Void) {
        Task { @MainActor in completion(Self.load()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ActivityEntry>) -> Void) {
        Task { @MainActor in
            let entry = Self.load()
            let refresh = Calendar.current.date(byAdding: .minute, value: 30, to: entry.date)
                ?? entry.date.addingTimeInterval(1800)
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
        let from = calendar.key(byAdding: -(days + 1), to: today)
        let logs = (try? repository.logs(from: from, to: today)) ?? []
        return ActivityEntry(
            date: Date(),
            matrix: HabitMatrix.build(habits: habits, logs: logs, calendar: calendar, today: today, days: days),
            calendar: calendar,
            today: today,
            availablePresets: HabitPreset.allCases.filter { preset in
                !habits.contains { $0.rule == preset.rule }
            }
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
        .configurationDisplayName("Week by habit")
        .description("Each habit as its own row, in its own colour. The large size can also add a habit.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct ActivityWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ActivityEntry

    private var isLarge: Bool { family == .systemLarge }

    // Content room is about 306x126 on medium and 306x322 on large.
    private var gap: CGFloat { isLarge ? 4 : 3 }
    private var labelWidth: CGFloat { isLarge ? 96 : 78 }
    private var maxRows: Int { isLarge ? 5 : 3 }
    private var cell: CGFloat {
        let fits = HabitMatrixView.cellThatFits(width: 306, days: ActivityProvider.days,
                                                gap: gap, labelWidth: labelWidth)
        return min(isLarge ? 26 : 22, fits)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isLarge ? 12 : 8) {
            if entry.hasHabits {
                HabitMatrixView(
                    matrix: entry.matrix, calendar: entry.calendar, today: entry.today,
                    cell: cell, gap: gap, labelWidth: labelWidth,
                    showsDayHeader: true, showsCounts: isLarge, maxRows: maxRows
                )
            } else {
                Text("No habits yet").font(.subheadline.bold())
                Text("Pick one below to start.").font(.caption).foregroundStyle(.secondary)
            }

            if isLarge {
                Spacer(minLength: 0)
                quickAdd
            }
        }
        .widgetURL(URL(string: "habitflow://today"))
    }

    /// A widget cannot show a form, so it offers ready-made habits and a door to the editor.
    private var quickAdd: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Add a habit").font(.system(size: 10)).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(entry.availablePresets) { preset in
                    Button(intent: QuickAddHabitIntent(preset: preset)) {
                        chip(emoji: preset.emoji, title: preset.title, detail: preset.goalLabel)
                    }
                    .buttonStyle(.plain)
                }
                Link(destination: URL(string: "habitflow://new")!) {
                    chip(emoji: "＋", title: String(localized: "Own"), detail: String(localized: "in the app"))
                }
            }
        }
    }

    private func chip(emoji: String, title: String, detail: String) -> some View {
        VStack(spacing: 1) {
            Text(emoji).font(.system(size: 15))
            Text(title).font(.system(size: 10, weight: .semibold)).lineLimit(1)
            Text(detail).font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

#Preview("Medium", as: .systemMedium) {
    ActivityWidget()
} timeline: {
    ActivityEntry.placeholder
}
