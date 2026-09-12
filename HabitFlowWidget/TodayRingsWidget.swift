import SwiftUI
import WidgetKit
import HabitCore

struct TodayRingsWidget: Widget {
    let kind = "TodayRings"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayRingsProvider()) { entry in
            TodayRingsEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today's habits")
        .description("Live rings for the habits HabitFlow tracks automatically.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TodayRingsEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayRingsEntry

    var body: some View {
        switch family {
        case .systemMedium: medium
        default: small
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if entry.items.isEmpty {
                Spacer()
                Text("Add a habit in HabitFlow").font(.caption).foregroundStyle(.secondary)
                Spacer()
            } else {
                HStack(spacing: 10) {
                    ForEach(entry.items.prefix(3)) { item in
                        ring(item, size: 40, lineWidth: 4)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .widgetURL(URL(string: "habitflow://today"))
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if entry.items.isEmpty {
                Text("Add a habit in HabitFlow").font(.caption).foregroundStyle(.secondary)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(entry.items.prefix(6)) { item in
                        VStack(spacing: 4) {
                            ring(item, size: 40, lineWidth: 4)
                            Text(item.name).font(.caption2).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .widgetURL(URL(string: "habitflow://today"))
    }

    private var header: some View {
        HStack {
            Text("\(entry.completedCount)/\(entry.items.count)")
                .font(.headline.monospacedDigit())
            Spacer()
            if let updatedAt = entry.updatedAt {
                Text(updatedAt, style: .relative)
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func ring(_ item: RingItem, size: CGFloat, lineWidth: CGFloat) -> some View {
        ProgressRing(ratio: item.ratio, color: Color(hex: item.colorHex), lineWidth: lineWidth, completed: item.completed) {
            Text(item.emoji).font(.system(size: size * 0.4))
        }
        .frame(width: size, height: size)
        .accessibilityLabel("\(item.name), \(item.completed ? "done" : item.progressText)")
    }
}

#Preview("Small", as: .systemSmall) {
    TodayRingsWidget()
} timeline: {
    TodayRingsEntry.placeholder
}

#Preview("Medium", as: .systemMedium) {
    TodayRingsWidget()
} timeline: {
    TodayRingsEntry.placeholder
}
