import Foundation
import SwiftData
@testable import HabitCore

final class FakeClock: @unchecked Sendable {
    var now: Date
    init(_ now: Date) { self.now = now }
    func advance(by seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

@MainActor
final class FakeProvider: HabitSourceProvider {
    let supportedKinds: Set<HabitSourceKind>
    var isAvailable = true
    /// Observed value per habit id.
    var values: [UUID: Double] = [:]
    var error: Error?
    var snapshotCalls = 0
    var lastWindow: DateInterval?
    var observing = false
    var authorizationRequests = 0

    init(kinds: Set<HabitSourceKind>) { self.supportedKinds = kinds }

    func requestAuthorization(for rules: [HabitRule]) async throws { authorizationRequests += 1 }

    func snapshot(for rule: HabitRule, habitID: UUID, window: DateInterval, now: Date) async throws -> ProgressSnapshot {
        snapshotCalls += 1
        lastWindow = window
        if let error { throw error }
        return ProgressSnapshot(value: values[habitID] ?? 0, target: rule.target, observedAt: now)
    }

    func startObserving(habits: [(id: UUID, rule: HabitRule)], onChange: @escaping @MainActor (HabitSourceKind) async -> Void) {
        observing = true
    }

    func stopObserving() { observing = false }
}

struct TestError: Error {}

/// Fixed calendar so tests don't depend on the machine's timezone.
enum Fixed {
    static let timeZone = TimeZone(identifier: "America/New_York")!
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }
    static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d; comps.hour = h; comps.minute = min
        return calendar.date(from: comps)!
    }
}

@MainActor
struct TestEnv {
    let container: ModelContainer
    let repository: SwiftDataHabitRepository
    let settings: AppSettings
    let registry: ProviderRegistry
    let health: FakeProvider
    let location: FakeProvider
    let clock: FakeClock
    let engine: AutoTrackingEngine
    var completions: [CompletionEvent] = []

    init(now: Date = Fixed.date(2026, 9, 12, 10, 0)) throws {
        container = try ModelContainerFactory.inMemory()
        repository = SwiftDataHabitRepository(container: container)
        let defaults = UserDefaults(suiteName: "HabitCoreTests-\(UUID().uuidString)")!
        settings = AppSettings(defaults: defaults)
        registry = ProviderRegistry()
        health = FakeProvider(kinds: [.healthQuantity, .healthSleep, .healthMindful, .healthWorkout])
        location = FakeProvider(kinds: [.geofence])
        registry.register(health)
        registry.register(location)
        clock = FakeClock(now)
        let clockRef = clock
        engine = AutoTrackingEngine(repository: repository, providers: registry, settings: settings, clock: { clockRef.now })
    }

    @discardableResult
    func addHabit(_ name: String, rule: HabitRule, scheduleMask: Int = Habit.everyDayMask) throws -> Habit {
        let habit = Habit(name: name, rule: rule, scheduleMask: scheduleMask, createdAt: clock.now.addingTimeInterval(-3600))
        repository.insert(habit)
        try repository.save()
        return habit
    }

    var today: DayKey { engine.dayCalendar.dayKey(for: clock.now) }

    func log(_ habit: Habit) throws -> DailyLog? { try repository.log(habitID: habit.id, dayKey: today) }
}
