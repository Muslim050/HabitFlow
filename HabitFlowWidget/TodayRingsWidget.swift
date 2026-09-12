import AppIntents
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
        .description("Rings for today's habits. Tap a ring or a row to mark it done.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct TodayRingsEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayRingsEntry

    var body: some View {
        switch family {
        // 6 two-line rows plus a header need 260 of the large box's 322.
        case .systemLarge: list(maxRows: 6, compact: false)
        // 3 one-line rows plus a header need 114 of the medium box's 126; four two-line
        // rows needed 184, which is why the last one was cut off.
        case .systemMedium: list(maxRows: 3, compact: true)
        default: small
        }
    }

    // MARK: Small: up to three tappable rings

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
                        Button(intent: ToggleHabitIntent(habitID: item.id, completed: !item.completed)) {
                            ring(item, size: 40, lineWidth: 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Medium / large: rows with a check button

    private func list(maxRows: Int, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 6) {
            header
            if entry.items.isEmpty {
                Text("Add a habit in HabitFlow").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(entry.items.prefix(maxRows)) { item in
                    Button(intent: ToggleHabitIntent(habitID: item.id, completed: !item.completed)) {
                        row(item, compact: compact)
                    }
                    .buttonStyle(.plain)
                }
                if entry.items.count > maxRows {
                    Text("+\(entry.items.count - maxRows) more").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func row(_ item: RingItem, compact: Bool) -> some View {
        if compact {
            // Name and progress share one line, so the row is as tall as its ring.
            HStack(spacing: 9) {
                ring(item, size: 26, lineWidth: 3)
                Text(item.name)
                    .font(.footnote.weight(.medium))
                    .strikethrough(item.completed)
                    .lineLimit(1)
                if !item.progressText.isEmpty {
                    Text(item.progressText)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .layoutPriority(-1)
                }
                Spacer(minLength: 2)
                Image(systemName: item.completed ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundStyle(item.completed ? Color(hex: item.colorHex) : Color.secondary)
            }
        } else {
            HStack(spacing: 10) {
                ring(item, size: 30, lineWidth: 3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name)
                        .font(.subheadline.weight(.medium))
                        .strikethrough(item.completed)
                        .lineLimit(1)
                    if !item.progressText.isEmpty {
                        Text(item.progressText).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: item.completed ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.completed ? Color(hex: item.colorHex) : Color.secondary)
            }
        }
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
        .accessibilityLabel(item.completed ? Text("\(item.name), done") : Text("\(item.name), \(item.progressText)"))
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
