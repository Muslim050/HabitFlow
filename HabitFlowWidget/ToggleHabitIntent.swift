import AppIntents
import Foundation
import SwiftData
import HabitCore

/// Runs inside the widget extension when a ring/row is tapped. Writes the shared store directly
/// (so the widget re-renders immediately) and queues the action for the app to replay.
struct ToggleHabitIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle habit"
    static let description = IntentDescription("Marks a habit done or not done for today.")
    static let isDiscoverable = false

    @Parameter(title: "Habit")
    var habitID: String

    @Parameter(title: "Completed")
    var completed: Bool

    init() {}

    init(habitID: UUID, completed: Bool) {
        self.habitID = habitID.uuidString
        self.completed = completed
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: habitID) else { return .result() }
        let settings = AppSettings.shared
        let container = try ModelContainerFactory.shared()
        let repository = SwiftDataHabitRepository(container: container)
        let engine = AutoTrackingEngine(repository: repository, providers: ProviderRegistry(), settings: settings)
        let dayKey = settings.dayCalendar.today()
        try engine.setManualCompletion(habitID: id, completed: completed, dayKey: dayKey)
        WidgetActionQueue.enqueue(WidgetAction(habitID: id, completed: completed, dayKey: dayKey, at: Date()))
        return .result()
    }
}
