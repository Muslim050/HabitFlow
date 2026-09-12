import BackgroundTasks
import Foundation

/// Daily reconciliation. Unreliable by design (system discretion) and never fires in the Simulator;
/// the real-time paths are HealthKit background delivery and region monitoring.
enum BackgroundRefresh {
    static let identifier = "com.muslimahaev.habitflow.refresh"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refresh)
        }
    }

    private static func handle(_ task: BGAppRefreshTask) {
        schedule()
        let work = Task { @MainActor in
            let env = AppEnvironment.shared
            await env.reconcileDayRollover()
            let summary = await env.engine.evaluateAll(reason: .backgroundRefresh)
            Log.background.info("BG refresh evaluated \(summary.evaluatedHabitIDs.count) habits, \(summary.completions.count) completions")
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    /// Earliest of: 4 h from now, or 30 min before the next logical day starts.
    static func schedule(earliest: Date? = nil) {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = earliest ?? Date().addingTimeInterval(4 * 3600)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            Log.background.error("Could not schedule refresh: \(error.localizedDescription)")
        }
    }
}
