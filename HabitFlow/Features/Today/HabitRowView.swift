import SwiftUI
import HabitCore

struct HabitRowView: View {
    @Environment(AppEnvironment.self) private var env
    let habit: Habit
    let log: DailyLog?

    private var isCompleted: Bool { log?.isCompleted ?? false }
    private var ratio: Double { log?.ratio ?? 0 }
    private var color: Color { Color(hex: habit.colorHex) }
    private var isOverridden: Bool { log?.completionSource == .manualOverride }

    var body: some View {
        NavigationLink(value: habit) {
            HStack(spacing: 14) {
                ProgressRing(ratio: ratio, color: color, lineWidth: 4, completed: isCompleted) {
                    Text(habit.emoji).font(.title3)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(habit.name)
                        .font(.body.weight(.medium))
                        .strikethrough(isCompleted, color: .secondary)
                        .foregroundStyle(isCompleted ? .secondary : .primary)
                    subtitle
                }
                Spacer(minLength: 8)

                // Every habit can be ticked by hand. For automatic ones this becomes a manual override
                // for the day; the ring keeps showing live progress underneath.
                Button {
                    toggle()
                } label: {
                    Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(isCompleted ? color : Color.secondary)
                        .symbolEffect(.bounce, value: isCompleted)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isCompleted ? Text("Mark not done") : Text("Mark done"))
            }
            .padding(.vertical, 4)
        }
        .contextMenu { contextMenu }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { archive() } label: { Label("Archive", systemImage: "archivebox") }
        }
    }

    @ViewBuilder
    private var subtitle: some View {
        if habit.isAutomatic {
            HStack(spacing: 6) {
                Text(progressText)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                if let source = habit.rule.sourceLabel {
                    Label {
                        Text(isOverridden ? String(localized: "Manual") : source)
                    } icon: {
                        Image(systemName: isOverridden ? "hand.tap" : habit.rule.systemImage)
                    }
                    .font(.caption2.weight(.semibold))
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.12), in: Capsule())
                    .foregroundStyle(color)
                }
            }
        } else {
            Text(isCompleted ? "Done" : "Tap the circle when done")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var progressText: String {
        guard let log else { return ValueFormatting.goal(target: habit.rule.target, unit: habit.rule.unitLabel) }
        return ValueFormatting.progress(value: log.progressValue, target: log.targetValue, unit: habit.rule.unitLabel)
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button {
            toggle()
        } label: {
            Label(isCompleted ? "Mark not done" : "Mark done", systemImage: isCompleted ? "xmark.circle" : "checkmark.circle")
        }
        if isOverridden {
            Button {
                Task { try? await env.engine.clearOverride(habitID: habit.id) }
            } label: { Label("Let auto-tracking decide", systemImage: "arrow.clockwise") }
        }
        Button(role: .destructive) { archive() } label: { Label("Archive", systemImage: "archivebox") }
    }

    private func toggle() {
        try? env.engine.setManualCompletion(habitID: habit.id, completed: !isCompleted)
    }

    private func archive() {
        habit.archivedAt = Date()
        habit.updatedAt = Date()
        try? env.repository.save()
        env.habitDidChange(nil)
    }
}
