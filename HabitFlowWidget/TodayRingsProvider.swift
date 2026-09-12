import Foundation
import SwiftData
import WidgetKit
import HabitCore

struct RingItem: Identifiable, Sendable {
    let id: UUID
    let emoji: String
    let name: String
    let colorHex: String
    let ratio: Double
    let completed: Bool
    let progressText: String
}

struct TodayRingsEntry: TimelineEntry {
    let date: Date
    let items: [RingItem]
    let completedCount: Int
    let updatedAt: Date?

    static let placeholder = TodayRingsEntry(
        date: Date(),
        items: [
            RingItem(id: UUID(), emoji: "🚶", name: "Walk", colorHex: "#4F8EF7", ratio: 0.72, completed: false, progressText: "5 800 / 8 000 steps"),
            RingItem(id: UUID(), emoji: "😴", name: "Sleep", colorHex: "#AF52DE", ratio: 1, completed: true, progressText: "7.5 / 7 h"),
            RingItem(id: UUID(), emoji: "📚", name: "Read", colorHex: "#FF9500", ratio: 0, completed: false, progressText: ""),
        ],
        completedCount: 1,
        updatedAt: Date()
    )
}

struct TodayRingsProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayRingsEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (TodayRingsEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }
        Task { @MainActor in completion(Self.load()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayRingsEntry>) -> Void) {
        Task { @MainActor in
            let entry = Self.load()
            let refresh = Calendar.current.date(byAdding: .minute, value: 30, to: entry.date) ?? entry.date.addingTimeInterval(1800)
            completion(Timeline(entries: [entry], policy: .after(refresh)))
        }
    }

    /// Reads the shared App Group store. Read-only: the widget never writes.
    @MainActor
    static func load() -> TodayRingsEntry {
        let now = Date()
        let settings = AppSettings.shared
        let calendar = settings.dayCalendar
        let today = calendar.dayKey(for: now)
        let weekday = calendar.weekday(for: today)

        guard let container = try? ModelContainerFactory.shared() else {
            return TodayRingsEntry(date: now, items: [], completedCount: 0, updatedAt: settings.lastEngineRunAt)
        }
        let repository = SwiftDataHabitRepository(container: container)
        let habits = ((try? repository.activeHabits()) ?? []).filter { $0.isScheduled(weekday: weekday) }
        let logs = (try? repository.logs(dayKey: today)) ?? []

        let items = habits.map { habit -> RingItem in
            let log = logs.first { $0.habitID == habit.id }
            let text: String
            if habit.isAutomatic {
                text = log.map { ValueFormatting.progress(value: $0.progressValue, target: $0.targetValue, unit: habit.rule.unitLabel) }
                    ?? ValueFormatting.goal(target: habit.rule.target, unit: habit.rule.unitLabel)
            } else {
                text = (log?.isCompleted ?? false) ? "Done" : ""
            }
            return RingItem(
                id: habit.id, emoji: habit.emoji, name: habit.name, colorHex: habit.colorHex,
                ratio: log?.ratio ?? 0, completed: log?.isCompleted ?? false, progressText: text
            )
        }
        return TodayRingsEntry(
            date: now, items: items,
            completedCount: items.filter(\.completed).count,
            updatedAt: settings.lastEngineRunAt
        )
    }
}
