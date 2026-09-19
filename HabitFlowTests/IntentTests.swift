import AppIntents
import Foundation
import SwiftData
import Testing
import HabitCore
@testable import HabitFlow

/// The Shortcuts side of the app. Driving the real Shortcuts UI cannot be automated reliably,
/// so what is pinned here is the part that is ours: what each intent does to the store.
@Suite("Intents")
@MainActor
struct IntentTests {
    /// An isolated store standing in for the app's one environment.
    private func environment() throws -> (repository: SwiftDataHabitRepository, settings: AppSettings) {
        let repository = SwiftDataHabitRepository(container: try ModelContainerFactory.inMemory())
        let defaults = UserDefaults(suiteName: "IntentTests-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        let engine = AutoTrackingEngine(repository: repository, providers: ProviderRegistry(), settings: settings)
        IntentRuntime.override = {
            IntentRuntime.Context(repository: repository, engine: engine, settings: settings)
        }
        return (repository, settings)
    }

    private func habit(_ repository: SwiftDataHabitRepository, _ name: String,
                       rule: HabitRule = .manual) throws -> Habit {
        let habit = Habit(name: name, rule: rule, createdAt: Date().addingTimeInterval(-30 * 86_400))
        repository.insert(habit)
        try repository.save()
        return habit
    }

    // MARK: The entity Shortcuts picks from

    @Test func theQueryOffersActiveHabitsAndFindsThemByName() async throws {
        let (repository, _) = try environment()
        defer { IntentRuntime.override = nil }
        let walk = try habit(repository, "Walk")
        let archived = try habit(repository, "Read")
        archived.archivedAt = Date()
        try repository.save()

        let query = HabitEntityQuery()
        let suggested = try await query.suggestedEntities()
        #expect(suggested.map(\.name) == ["Walk"], "an archived habit is not something to log")

        #expect(try await query.entities(matching: "wal").map(\.id) == [walk.id], "search is case-insensitive")
        #expect(try await query.entities(for: [walk.id]).count == 1, "a saved shortcut resolves its habit by id")
    }

    // MARK: Marking

    @Test func completingWritesTheDay() async throws {
        let (repository, settings) = try environment()
        defer { IntentRuntime.override = nil }
        let walk = try habit(repository, "Walk")

        _ = try await CompleteHabitIntent(habit: HabitEntity(walk)).perform()

        let today = settings.dayCalendar.today()
        let log = try #require(try repository.log(habitID: walk.id, dayKey: today))
        #expect(log.isCompleted)
        #expect(log.completionSource == .manual)
    }

    @Test func completingAPastDayWritesThatDay() async throws {
        let (repository, settings) = try environment()
        defer { IntentRuntime.override = nil }
        let walk = try habit(repository, "Walk")
        let threeDaysAgo = Date().addingTimeInterval(-3 * 86_400)

        _ = try await CompleteHabitIntent(habit: HabitEntity(walk), day: threeDaysAgo).perform()

        let key = settings.dayCalendar.dayKey(for: threeDaysAgo)
        #expect(try repository.log(habitID: walk.id, dayKey: key)?.isCompleted == true)
        #expect(try repository.log(habitID: walk.id, dayKey: settings.dayCalendar.today()) == nil,
                "only the day that was asked for")
    }

    @Test func aMeasuredValueIsJudgedAgainstTheTarget() async throws {
        let (repository, settings) = try environment()
        defer { IntentRuntime.override = nil }
        let walk = try habit(repository, "Walk", rule: .healthQuantity(metric: .steps, target: 8000))

        _ = try await CompleteHabitIntent(habit: HabitEntity(walk), value: 9000).perform()

        let log = try #require(try repository.log(habitID: walk.id, dayKey: settings.dayCalendar.today()))
        #expect(log.progressValue == 9000)
        #expect(log.isCompleted)
        #expect(log.completionSource == .manualOverride)
    }

    @Test func aValueOnAPlainTickIsRefusedRatherThanInvented() async throws {
        let (repository, _) = try environment()
        defer { IntentRuntime.override = nil }
        let read = try habit(repository, "Read")

        await #expect(throws: HabitIntentError.notMeasured("Read")) {
            _ = try await CompleteHabitIntent(habit: HabitEntity(read), value: 3).perform()
        }
    }

    @Test func aDayOutsideTheEditableRangeIsRefusedWithSomethingReadable() async throws {
        let (repository, settings) = try environment()
        defer { IntentRuntime.override = nil }
        settings.backdateLimitDays = 7
        let walk = try habit(repository, "Walk")

        await #expect(throws: HabitIntentError.dayNotEditable) {
            _ = try await CompleteHabitIntent(habit: HabitEntity(walk),
                                              day: Date().addingTimeInterval(-20 * 86_400)).perform()
        }
    }

    @Test func clearingRemovesTheMark() async throws {
        let (repository, settings) = try environment()
        defer { IntentRuntime.override = nil }
        let walk = try habit(repository, "Walk")
        _ = try await CompleteHabitIntent(habit: HabitEntity(walk)).perform()

        _ = try await UncompleteHabitIntent(habit: HabitEntity(walk)).perform()

        let log = try #require(try repository.log(habitID: walk.id, dayKey: settings.dayCalendar.today()))
        #expect(!log.isCompleted)
    }

    // MARK: Pausing

    @Test func pausingWithAnEndDateStopsAskingUntilThen() async throws {
        let (repository, settings) = try environment()
        defer { IntentRuntime.override = nil }
        let walk = try habit(repository, "Walk")
        let until = Date().addingTimeInterval(5 * 86_400)

        _ = try await PauseHabitIntent(habit: HabitEntity(walk), until: until).perform()

        let pauses = try repository.pauses()
        #expect(pauses.count == 1)
        let span = try #require(pauses.first?.span)
        #expect(span.start == settings.dayCalendar.today())
        #expect(span.end == settings.dayCalendar.dayKey(for: until))
        #expect(!walk.isDue(on: settings.dayCalendar.today(), calendar: settings.dayCalendar,
                            pauses: pauses.spans(for: walk.id)))
    }

    @Test func pausingWithoutAnEndDateRunsUntilResumed() async throws {
        let (repository, _) = try environment()
        defer { IntentRuntime.override = nil }
        let walk = try habit(repository, "Walk")

        _ = try await PauseHabitIntent(habit: HabitEntity(walk)).perform()

        #expect(try repository.pauses().first?.isRunning == true)
    }

    @Test func pausingAHabitThatIsGoneSaysSoRatherThanFailingQuietly() async throws {
        let (repository, _) = try environment()
        defer { IntentRuntime.override = nil }
        let walk = try habit(repository, "Walk")
        let entity = HabitEntity(walk)
        repository.delete(walk)
        try repository.save()

        await #expect(throws: HabitIntentError.habitMissing) {
            _ = try await PauseHabitIntent(habit: entity).perform()
        }
    }
}
