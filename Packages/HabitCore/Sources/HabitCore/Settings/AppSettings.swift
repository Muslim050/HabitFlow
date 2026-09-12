import Foundation

/// Small settings store backed by the App Group `UserDefaults` so the widget sees the same values.
public final class AppSettings: @unchecked Sendable {
    public enum Key {
        public static let dayStartHour = "dayStartHour"
        public static let nudgeHour = "nudgeHour"
        public static let nudgeEnabled = "nudgeEnabled"
        public static let graceMissesPerWeek = "graceMissesPerWeek"
        public static let hasCompletedOnboarding = "hasCompletedOnboarding"
        public static let healthAuthorizationRequested = "healthAuthorizationRequested"
        public static let lastEngineRunAt = "lastEngineRunAt"
        public static let defaultAdaptationMode = "defaultAdaptationMode"
        public static let agendaEnabled = "agendaEnabled"
    }

    public static let store: UserDefaults = UserDefaults(suiteName: AppGroup.id) ?? .standard
    public static let shared = AppSettings(defaults: AppSettings.store)

    public let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public var dayStartHour: Int {
        get { defaults.object(forKey: Key.dayStartHour) as? Int ?? 4 }
        set { defaults.set(min(max(newValue, 0), 6), forKey: Key.dayStartHour) }
    }

    public var nudgeHour: Int {
        get { defaults.object(forKey: Key.nudgeHour) as? Int ?? 20 }
        set { defaults.set(min(max(newValue, 0), 23), forKey: Key.nudgeHour) }
    }

    public var nudgeEnabled: Bool {
        get { defaults.object(forKey: Key.nudgeEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.nudgeEnabled) }
    }

    public var graceMissesPerWeek: Int {
        get { defaults.object(forKey: Key.graceMissesPerWeek) as? Int ?? 1 }
        set { defaults.set(min(max(newValue, 0), 3), forKey: Key.graceMissesPerWeek) }
    }

    public var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Key.hasCompletedOnboarding) }
        set { defaults.set(newValue, forKey: Key.hasCompletedOnboarding) }
    }

    public var healthAuthorizationRequested: Bool {
        get { defaults.bool(forKey: Key.healthAuthorizationRequested) }
        set { defaults.set(newValue, forKey: Key.healthAuthorizationRequested) }
    }

    public var lastEngineRunAt: Date? {
        get { defaults.object(forKey: Key.lastEngineRunAt) as? Date }
        set { defaults.set(newValue, forKey: Key.lastEngineRunAt) }
    }

    /// Applied to newly created habits that have an adjustable goal.
    public var defaultAdaptationMode: GoalAdaptationMode {
        get { GoalAdaptationMode(rawValue: defaults.string(forKey: Key.defaultAdaptationMode) ?? "") ?? .suggest }
        set { defaults.set(newValue.rawValue, forKey: Key.defaultAdaptationMode) }
    }

    /// Shows today's calendar events and due reminders under the habits. Off until asked for.
    public var agendaEnabled: Bool {
        get { defaults.bool(forKey: Key.agendaEnabled) }
        set { defaults.set(newValue, forKey: Key.agendaEnabled) }
    }

    public var dayCalendar: DayCalendar { DayCalendar(dayStartHour: dayStartHour) }
}
