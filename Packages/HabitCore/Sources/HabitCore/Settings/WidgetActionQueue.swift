import Foundation

/// Manual toggles made from the interactive widget. The widget is a separate process: it writes
/// the store itself so the widget re-renders instantly, and the app replays the queue on
/// foreground so its own (possibly stale) `ModelContext` ends up with the same state. Replaying
/// is idempotent.
///
/// Shortcuts do not go through here — an app-target intent runs inside the app's own process and
/// has already written through its context.
public struct WidgetAction: Codable, Sendable, Equatable {
    public var habitID: UUID
    public var completed: Bool
    public var dayKey: DayKey
    public var at: Date

    public init(habitID: UUID, completed: Bool, dayKey: DayKey, at: Date) {
        self.habitID = habitID
        self.completed = completed
        self.dayKey = dayKey
        self.at = at
    }
}

public enum WidgetActionQueue {
    public static let key = "pendingWidgetActions"

    public static func enqueue(_ action: WidgetAction, defaults: UserDefaults = AppSettings.store) {
        var actions = pending(defaults: defaults)
        actions.removeAll { $0.habitID == action.habitID && $0.dayKey == action.dayKey }
        actions.append(action)
        defaults.set(try? JSONEncoder().encode(actions), forKey: key)
    }

    public static func pending(defaults: UserDefaults = AppSettings.store) -> [WidgetAction] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([WidgetAction].self, from: data)) ?? []
    }

    /// Returns and clears the queue.
    public static func drain(defaults: UserDefaults = AppSettings.store) -> [WidgetAction] {
        let actions = pending(defaults: defaults)
        defaults.removeObject(forKey: key)
        return actions
    }
}
