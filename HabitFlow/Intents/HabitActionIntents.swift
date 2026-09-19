import AppIntents
import Foundation
import SwiftData
import WidgetKit
import HabitCore

/// Failures a Shortcut can hit, worded for someone who is looking at a Shortcuts error and not
/// at the code.
enum HabitIntentError: Error, Equatable, CustomLocalizedStringResourceConvertible {
    case dayNotEditable
    case notMeasured(String)
    case habitMissing

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .dayNotEditable:
            return "That day is outside the range you can still edit."
        case .notMeasured(let name):
            return "\(name) is a plain tick, so there is no value to set."
        case .habitMissing:
            return "That habit no longer exists."
        }
    }
}

/// Shared plumbing. An intent may run with the app closed, but it still runs *inside the app's
/// process*, so it must use the one container the app already opened. Building a second
/// `ModelContainer` over the same store resets the first one's context and every live model
/// object with it — which is exactly how this crashed the first time it was run for real.
@MainActor
enum IntentRuntime {
    struct Context {
        var repository: SwiftDataHabitRepository
        var engine: AutoTrackingEngine
        var settings: AppSettings
    }

    /// Replaced by the tests with an in-memory store. Nothing in the app ever sets it: production
    /// always goes through the app's one environment.
    static var override: (() -> Context)?

    static func context() throws -> Context {
        if let override { return override() }
        let environment = AppEnvironment.shared
        return Context(repository: environment.repository, engine: environment.engine,
                       settings: environment.settings)
    }

    /// The picker hands over a civil date; the store thinks in logical days. Converting by
    /// components rather than through `dayKey(for:)` keeps midnight from landing on yesterday
    /// whenever the day starts after 00:00.
    static func dayKey(for date: Date?, settings: AppSettings) -> DayKey {
        let calendar = settings.dayCalendar
        guard let date else { return calendar.today() }
        let parts = calendar.calendar.dateComponents([.year, .month, .day], from: date)
        return DayKey(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0)
    }

    /// No queueing here, unlike the widget: this ran through the app's own context, so there is
    /// nothing for the app to replay. Only the widget, which is a separate process, needs that.
    static func finish() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func mapping<T>(_ work: () throws -> T) throws -> T {
        do {
            return try work()
        } catch BackdateError.dayNotEditable {
            throw HabitIntentError.dayNotEditable
        }
    }
}

// MARK: Mark done

struct CompleteHabitIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark habit done"
    static let description = IntentDescription("Marks a habit done, optionally on a past day or with a measured value.")
    static let openAppWhenRun = false

    @Parameter(title: "Habit")
    var habit: HabitEntity

    @Parameter(title: "Day", description: "Leave empty for today.")
    var day: Date?

    @Parameter(title: "Value", description: "For habits that measure something, such as steps or minutes.")
    var value: Double?

    static var parameterSummary: some ParameterSummary {
        Summary("Mark \(\.$habit) done") {
            \.$day
            \.$value
        }
    }

    init() {}

    init(habit: HabitEntity, day: Date? = nil, value: Double? = nil) {
        self.habit = habit
        self.day = day
        self.value = value
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = try IntentRuntime.context()
        let key = IntentRuntime.dayKey(for: day, settings: context.settings)

        if let value {
            guard habit.isMeasured else { throw HabitIntentError.notMeasured(habit.name) }
            try IntentRuntime.mapping {
                try context.engine.setManualValue(habitID: habit.id, value: value, dayKey: key)
            }
                IntentRuntime.finish()
            return .result(dialog: "Recorded \(ValueFormatting.progressless(target: value, unit: habit.unit)) for \(habit.name).")
        }

        try IntentRuntime.mapping {
            try context.engine.setManualCompletion(habitID: habit.id, completed: true, dayKey: key)
        }
        IntentRuntime.finish()
        return .result(dialog: "\(habit.name) is done.")
    }
}

// MARK: Clear the mark

struct UncompleteHabitIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark habit not done"
    static let description = IntentDescription("Clears a habit's mark for today or a past day.")
    static let openAppWhenRun = false

    @Parameter(title: "Habit")
    var habit: HabitEntity

    @Parameter(title: "Day", description: "Leave empty for today.")
    var day: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Mark \(\.$habit) not done") {
            \.$day
        }
    }

    init() {}

    init(habit: HabitEntity, day: Date? = nil) {
        self.habit = habit
        self.day = day
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = try IntentRuntime.context()
        let key = IntentRuntime.dayKey(for: day, settings: context.settings)
        try IntentRuntime.mapping {
            try context.engine.setManualCompletion(habitID: habit.id, completed: false, dayKey: key)
        }
        IntentRuntime.finish()
        return .result(dialog: "\(habit.name) is no longer marked.")
    }
}

// MARK: Pause

struct PauseHabitIntent: AppIntent {
    static let title: LocalizedStringResource = "Pause habit"
    static let description = IntentDescription("Stops asking for a habit until a date, or until you resume it. Paused days are not counted against you.")
    static let openAppWhenRun = false

    @Parameter(title: "Habit")
    var habit: HabitEntity

    @Parameter(title: "Until", description: "Leave empty to pause until you resume it.")
    var until: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Pause \(\.$habit)") {
            \.$until
        }
    }

    init() {}

    init(habit: HabitEntity, until: Date? = nil) {
        self.habit = habit
        self.until = until
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = try IntentRuntime.context()
        guard try context.repository.habit(id: habit.id) != nil else { throw HabitIntentError.habitMissing }
        let today = context.settings.dayCalendar.today()
        let end = until.map { max(IntentRuntime.dayKey(for: $0, settings: context.settings), today) }

        context.repository.insert(HabitPause(habitID: habit.id, start: today, end: end, reason: .other))
        try context.repository.save()
        WidgetCenter.shared.reloadAllTimelines()

        if let end {
            let readable = end.formatted(calendar: context.settings.dayCalendar)
            return .result(dialog: "\(habit.name) is paused until \(readable).")
        }
        return .result(dialog: "\(habit.name) is paused until you resume it.")
    }
}
