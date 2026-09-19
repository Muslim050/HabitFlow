import AppIntents

/// What Siri and Spotlight offer without the user building a Shortcut first. Every phrase has to
/// contain the app name, which is what `\(.applicationName)` is for; translations live in
/// `AppShortcuts.xcstrings`, the one table App Shortcuts reads.
///
/// Only the app target may declare a provider — the widget compiles the intents themselves, but
/// the shortcuts belong to the app.
struct HabitFlowShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CompleteHabitIntent(),
            phrases: [
                "Mark a habit done in \(.applicationName)",
                "Log a habit in \(.applicationName)",
                "Tick off a habit in \(.applicationName)"
            ],
            shortTitle: "Mark done",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: UncompleteHabitIntent(),
            phrases: [
                "Clear a habit in \(.applicationName)",
                "Undo a habit in \(.applicationName)"
            ],
            shortTitle: "Mark not done",
            systemImageName: "xmark.circle"
        )
        AppShortcut(
            intent: PauseHabitIntent(),
            phrases: [
                "Pause a habit in \(.applicationName)",
                "Take a break from a habit in \(.applicationName)"
            ],
            shortTitle: "Pause",
            systemImageName: "pause.circle"
        )
    }
}
