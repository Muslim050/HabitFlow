import AppIntents
import Foundation
import SwiftData
import WidgetKit
import HabitCore

/// Creates a ready-made habit straight from the widget. A widget has no text input, so this
/// is the only kind of habit it can create on its own; anything custom opens the app.
struct QuickAddHabitIntent: AppIntent {
    static let title: LocalizedStringResource = "Add habit"
    static let description = IntentDescription("Creates one of the ready-made habits.")
    static let isDiscoverable = false

    @Parameter(title: "Preset")
    var presetID: String

    init() {}

    init(preset: HabitPreset) {
        presetID = preset.rawValue
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let preset = HabitPreset(rawValue: presetID) else { return .result() }
        let container = try ModelContainerFactory.shared()
        let repository = SwiftDataHabitRepository(container: container)
        let existing = try repository.activeHabits()
        // Tapping twice should not leave two identical habits behind.
        guard !existing.contains(where: { $0.rule == preset.rule }) else { return .result() }

        repository.insert(preset.makeHabit(sortOrder: existing.count))
        try repository.save()
        // HealthKit observers live in the app process, so tracking starts when the app is next
        // opened; the habit itself exists from this moment.
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
