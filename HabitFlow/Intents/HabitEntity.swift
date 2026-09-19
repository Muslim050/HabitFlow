import AppIntents
import Foundation
import HabitCore

/// A habit as Shortcuts and Spotlight see it.
///
/// App-target only, deliberately. An intent type declared in both the app and its extension
/// registers the same identifier twice, and the system's index does not enjoy that; the widget
/// keeps its own two private intents and the two sides meet at `WidgetActionQueue` instead.
struct HabitEntity: AppEntity, Identifiable, Hashable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Habit")
    static let defaultQuery = HabitEntityQuery()

    var id: UUID
    var name: String
    var emoji: String
    /// Whether the habit measures a number, so an intent can refuse a value where none fits.
    var isMeasured: Bool
    var unit: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(emoji) \(name)")
    }

    init(_ habit: Habit) {
        id = habit.id
        name = habit.name
        emoji = habit.emoji
        isMeasured = habit.isAutomatic
        unit = habit.rule.unitLabel
    }
}

struct HabitEntityQuery: EntityQuery, EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [HabitEntity] {
        try all().filter { identifiers.contains($0.id) }.map(HabitEntity.init)
    }

    /// What Shortcuts offers before the user types anything: archived habits are not useful here.
    @MainActor
    func suggestedEntities() async throws -> [HabitEntity] {
        try all().map(HabitEntity.init)
    }

    /// Spotlight and Siri search by name, so a partial, case-insensitive match is what is wanted.
    @MainActor
    func entities(matching string: String) async throws -> [HabitEntity] {
        try all()
            .filter { $0.name.localizedCaseInsensitiveContains(string) }
            .map(HabitEntity.init)
    }

    @MainActor
    private func all() throws -> [Habit] {
        try IntentRuntime.context().repository.activeHabits()
    }
}
