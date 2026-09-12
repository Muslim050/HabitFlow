# HabitFlow

A zero-tap habit tracker for iPhone: habits complete themselves from Health data
(steps, sleep, workouts, mindful minutes, water, active energy) and from places you
visit (geofences). Everything stays on the device.

## Layout

- `Packages/HabitCore` — domain, SwiftData models, auto-tracking engine, scoring. Tested with `make test-core` (runs on macOS, no simulator needed).
- `HabitFlow` — the iOS app (SwiftUI). HealthKit / CoreLocation providers, notifications, background tasks, screens.
- `HabitFlowWidget` — home-screen widget reading the shared App Group store.
- `project.yml` — XcodeGen spec. Run `make gen` to (re)create `HabitFlow.xcodeproj`.

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
