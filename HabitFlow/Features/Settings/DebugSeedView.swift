#if DEBUG
import EventKit
import HealthKit
import SwiftUI
import HabitCore

/// Writes sample data into Health so automatic habits can be exercised in the Simulator.
struct DebugSeedView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var message = ""

    var body: some View {
        List {
            Section("Write to Health") {
                Button("Add 9 000 steps (today)") { seed { try await seedQuantity(.steps, value: 9000) } }
                Button("Add 450 kcal active energy") { seed { try await seedQuantity(.activeEnergy, value: 450) } }
                Button("Add 750 ml water") { seed { try await seedQuantity(.water, value: 750) } }
                Button("Add 7.5 h sleep (last night)") { seed { try await seedSleep(hours: 7.5) } }
                Button("Add 12 mindful minutes") { seed { try await seedMindful(minutes: 12) } }
                Button("Add 35 min running workout") { seed { try await seedWorkout(minutes: 35) } }
            }
            Section("Calendar") {
                Button("Add an event and a reminder for today") { seedAgenda() }
            }
            Section("History") {
                Button("Fill 10 weeks of history") { seedHistory(weeks: 10) }
                Button("Clear history before today") { clearHistory() }
            }
            Section("Then") {
                Button("Run auto-tracking now") { Task { await env.engine.evaluateAll(reason: .manualRefresh) } }
            }
            if !message.isEmpty {
                Section { Text(message).font(.footnote) }
            }
        }
        .navigationTitle("Seed Health data")
    }

    private var store: HKHealthStore { env.healthKit.store }

    private func seed(_ work: @escaping () async throws -> Void) {
        Task {
            do {
                try await work()
                message = "Saved. Run auto-tracking to see the effect."
                await env.engine.evaluateAll(reason: .manualRefresh)
            } catch {
                message = "Failed: \(error.localizedDescription)"
            }
        }
    }

    /// Debug-only: paints plausible history so the activity grid and the scoring have
    /// something to show before a real week has passed.
    private func seedHistory(weeks: Int) {
        let calendar = env.settings.dayCalendar
        let today = env.currentDayKey
        var generator = SystemRandomNumberGenerator()
        do {
            let habits = try env.repository.activeHabits()
            let pauses = try env.repository.pauses()
            // A habit cannot have history from before it existed, so move its creation back
            // to the start of the seeded range.
            let firstDay = calendar.dayStart(for: calendar.key(byAdding: -(weeks * 7), to: today))
            for habit in habits where habit.createdAt > firstDay {
                habit.createdAt = firstDay
                habit.updatedAt = Date()
            }
            for offset in 1...(weeks * 7) {
                let key = calendar.key(byAdding: -offset, to: today)
                for habit in habits where habit.isDue(on: key, calendar: calendar, pauses: pauses.spans(for: habit.id)) {
                    // Recent weeks go better than older ones, so trends and streaks look real.
                    let bias = 0.45 + 0.4 * (1 - Double(offset) / Double(weeks * 7))
                    let hit = Double.random(in: 0...1, using: &generator) < bias
                    let target = habit.rule.target
                    let log = try env.repository.fetchOrCreateLog(
                        habitID: habit.id, dayKey: key,
                        dayStart: calendar.dayStart(for: key), target: target
                    )
                    log.targetValue = target
                    log.progressValue = hit ? target * Double.random(in: 1.0...1.4, using: &generator)
                                            : target * Double.random(in: 0.2...0.9, using: &generator)
                    log.isCompleted = hit
                    log.completionSource = hit ? .auto : .unset
                    log.completedAt = hit
                        ? calendar.dayStart(for: key).addingTimeInterval(Double.random(in: 4...16, using: &generator) * 3600)
                        : nil
                    log.lastEvaluatedAt = Date()
                }
            }
            try env.repository.save()
            env.analysis.refresh()
            message = "History filled for \(weeks) weeks."
        } catch {
            message = "Failed: \(error.localizedDescription)"
        }
    }

    /// Debug-only: writes one event and one reminder into the system stores so the
    /// "Also today" strip can be seen without typing into the Calendar app.
    private func seedAgenda() {
        Task {
            let store = EKEventStore()
            guard (try? await store.requestFullAccessToEvents()) == true else {
                message = "Calendar access refused."
                return
            }
            _ = try? await store.requestFullAccessToReminders()
            do {
                let event = EKEvent(eventStore: store)
                event.title = String(localized: "Project call")
                event.startDate = Date().addingTimeInterval(90 * 60)
                event.endDate = event.startDate.addingTimeInterval(45 * 60)
                event.calendar = store.defaultCalendarForNewEvents
                try store.save(event, span: .thisEvent)

                if let list = store.defaultCalendarForNewReminders() {
                    let reminder = EKReminder(eventStore: store)
                    reminder.title = String(localized: "Send the report")
                    reminder.calendar = list
                    reminder.dueDateComponents = Calendar.current.dateComponents(
                        [.year, .month, .day, .hour, .minute],
                        from: Date().addingTimeInterval(3 * 3600)
                    )
                    try store.save(reminder, commit: true)
                }
                await env.calendar.refresh()
                message = "Added to Calendar and Reminders."
            } catch {
                message = "Failed: \(error.localizedDescription)"
            }
        }
    }

    private func clearHistory() {
        let today = env.currentDayKey
        do {
            let from = env.settings.dayCalendar.key(byAdding: -400, to: today)
            for log in try env.repository.logs(from: from, to: today) where log.dayKey != today.raw {
                env.repository.delete(log)
            }
            try env.repository.save()
            env.analysis.refresh()
            message = "History cleared."
        } catch {
            message = "Failed: \(error.localizedDescription)"
        }
    }

    private func authorizeShare(_ types: Set<HKSampleType>) async throws {
        try await store.requestAuthorization(toShare: types, read: Set(types.map { $0 as HKObjectType }))
    }

    private func seedQuantity(_ metric: HealthMetric, value: Double) async throws {
        let type = HealthKitTypes.quantityType(for: metric)
        try await authorizeShare([type])
        let end = Date()
        let sample = HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: HealthKitTypes.unit(for: metric), doubleValue: value),
            start: end.addingTimeInterval(-1800),
            end: end
        )
        try await store.save(sample)
    }

    private func seedSleep(hours: Double) async throws {
        let type = HealthKitTypes.sleepType
        try await authorizeShare([type])
        let dayStart = env.settings.dayCalendar.dayStart(for: env.currentDayKey)
        let end = dayStart.addingTimeInterval(2.5 * 3600)   // 06:30 for a 04:00 day start
        let start = end.addingTimeInterval(-hours * 3600)   // crosses midnight
        let sample = HKCategorySample(
            type: type,
            value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            start: start,
            end: end
        )
        try await store.save(sample)
    }

    private func seedMindful(minutes: Double) async throws {
        let type = HealthKitTypes.mindfulType
        try await authorizeShare([type])
        let end = Date()
        let sample = HKCategorySample(type: type, value: HKCategoryValue.notApplicable.rawValue,
                                      start: end.addingTimeInterval(-minutes * 60), end: end)
        try await store.save(sample)
    }

    private func seedWorkout(minutes: Double) async throws {
        try await authorizeShare([HealthKitTypes.workoutType])
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        let end = Date()
        let start = end.addingTimeInterval(-minutes * 60)
        try await builder.beginCollection(at: start)
        try await builder.endCollection(at: end)
        _ = try await builder.finishWorkout()
    }
}
#endif
