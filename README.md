# HabitFlow

A zero-tap habit tracker for iPhone: habits complete themselves from Health data
(steps, sleep, workouts, mindful minutes, water, active energy) and from places you
visit (geofences). Everything stays on the device.

## Layout

- `Packages/HabitCore` — domain, SwiftData models, auto-tracking engine, scoring, insights and adaptive goals. Tested with `make test-core` (runs on macOS, no simulator needed).
- `HabitFlow` — the iOS app (SwiftUI). HealthKit / CoreLocation providers, notifications, background tasks, screens.
- `HabitFlowWidget` — interactive home-screen widget (small/medium/large). Tapping a ring or row runs `ToggleHabitIntent`, which writes the shared store and queues the action; the app replays the queue on foreground so its own context stays in sync.
- `project.yml` — XcodeGen spec. Run `make gen` to (re)create `HabitFlow.xcodeproj`.

## Insights and adaptive goals

`InsightEngine` looks for patterns (weekly trend, weak weekday, pairing between two habits, near miss,
typical time of day). Every rule has a minimum sample size and a minimum effect size, so a couple of
lucky days never produce a claim, and the wording stays associative rather than causal.

`GoalAdaptation` raises a goal when it is reached on at least 85% of the last 14 scheduled days with a
median result of 110% or more, and lowers it at 40% or less with a median of 80% or less. It needs 10
days of data, never moves the goal more than 50% at once, and waits 14 days after a change or a
dismissal. Each habit is fixed, suggesting, or automatic; the default for new habits is in Settings.

`AnalysisEngine` ties both to the store; the app wraps it in `AnalysisService` for the UI.

## Localization

English (source) and Russian. Strings live in String Catalogs: `HabitFlow/Resources/Localizable.xcstrings`,
`HabitFlow/Resources/InfoPlist.xcstrings`, `HabitFlowWidget/Localizable.xcstrings` and
`Packages/HabitCore/Sources/HabitCore/Resources/Localizable.xcstrings`. `SWIFT_EMIT_LOC_STRINGS` is on, so
new literals appear after `xcodebuild -exportLocalizations -exportLanguage ru`; add the Russian value to the catalog.
Run the app in Russian: `xcrun simctl launch booted com.muslimahaev.habitflow -AppleLanguages "(ru)"`.

## First-time setup

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
xcodebuild -runFirstLaunch
xcodebuild -downloadPlatform iOS
brew install xcodegen
make gen
make run
```

## Everyday commands

- `make test-core` — engine/scoring unit tests (seconds).
- `make build` / `make test` / `make run` — simulator build, app tests, install + launch.

## Simulator notes

- HealthKit queries and the permission sheet work in the Simulator. Use Settings → Developer → "Seed Health data" in a Debug build, or add samples in the Health app.
- HealthKit background delivery and `BGAppRefreshTask` never fire in the Simulator — test those on a device.
- Geofences: `xcrun simctl location booted set <lat>,<lon>` moves the simulated device.
