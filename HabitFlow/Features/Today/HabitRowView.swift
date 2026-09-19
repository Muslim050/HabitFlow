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
        HStack(spacing: 12) {
            NavigationLink(value: habit) {
                HStack(spacing: 12) {
                    HabitIconView(habit: habit)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(habit.name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(isCompleted ? HFTheme.secondaryInk : HFTheme.ink)
                        subtitle
                    }
                    Spacer(minLength: 2)
                }
            }
            .buttonStyle(.plain)

            // Every habit can be ticked by hand. For automatic ones this becomes a manual override
            // for the day; the live progress remains visible in the subtitle.
            Button { toggle() } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isCompleted ? color : Color.clear)
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isCompleted ? Color.clear : HFTheme.secondaryInk.opacity(0.45), lineWidth: 1.5)
                    if isCompleted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 42, height: 42)
                .contentShape(Rectangle())
                .symbolEffect(.bounce, value: isCompleted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isCompleted ? Text("Mark not done") : Text("Mark done"))
        }
        .padding(14)
        .background(HFTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(HFTheme.ink.opacity(0.055), lineWidth: 1)
        }
        .contextMenu { contextMenu }
    }

    @ViewBuilder
    private var subtitle: some View {
        if habit.isAutomatic {
            HStack(spacing: 7) {
                Text(progressText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(HFTheme.secondaryInk)
                if let source = habit.rule.sourceLabel {
                    Label {
                        Text(isOverridden ? String(localized: "Manual") : source)
                    } icon: {
                        Image(systemName: isOverridden ? "hand.tap" : habit.rule.systemImage)
                    }
                    .font(.system(size: 9, weight: .bold))
                    .labelStyle(.titleAndIcon)
                    .textCase(.uppercase)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(HFTheme.sage, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .foregroundStyle(HFTheme.accent)
                }
            }
        } else {
            Text(isCompleted ? "Done" : "Tap the circle when done")
                .font(.caption)
                .foregroundStyle(HFTheme.secondaryInk)
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
