import Foundation
import UserNotifications
import HabitCore

@MainActor
final class NotificationService: NSObject {
    enum Category {
        static let autoCompleted = "AUTO_COMPLETED"
        static let nudge = "NUDGE"
    }

    private let center = UNUserNotificationCenter.current()

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            Log.notifications.error("Authorization failed: \(error.localizedDescription)")
            return false
        }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    // MARK: Content builders (pure, unit-tested)

    nonisolated static func autoCompletedContent(for event: CompletionEvent) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "\(event.emoji) \(event.habitName) — done automatically"
        let progress = ValueFormatting.progress(value: event.value, target: event.target, unit: event.unitLabel)
        content.body = event.sourceLabel.isEmpty ? progress : "\(progress) from \(event.sourceLabel)"
        content.sound = .default
        content.categoryIdentifier = Category.autoCompleted
        content.threadIdentifier = "auto-\(event.dayKey.raw)"
        return content
    }

    nonisolated static func nudgeContent(unfinished: [String]) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = unfinished.count == 1 ? "One habit left today" : "\(unfinished.count) habits left today"
        content.body = unfinished.prefix(4).joined(separator: " · ") + (unfinished.count > 4 ? " …" : "")
        content.sound = .default
        content.categoryIdentifier = Category.nudge
        return content
    }

    nonisolated static func nudgeIdentifier(for dayKey: DayKey) -> String { "nudge-\(dayKey.raw)" }

    // MARK: Sending

    func sendAutoCompleted(_ event: CompletionEvent) async {
        let content = Self.autoCompletedContent(for: event)
        let request = UNNotificationRequest(
            identifier: "auto-\(event.habitID.uuidString)-\(event.dayKey.raw)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        do {
            try await center.add(request)
        } catch {
            Log.notifications.error("Auto-completed notification failed: \(error.localizedDescription)")
        }
    }

    /// One nudge per day at `hour`, listing what is still open. Removed when nothing is left.
    func scheduleNudge(unfinished: [String], hour: Int, dayKey: DayKey, enabled: Bool) async {
        let identifier = Self.nudgeIdentifier(for: dayKey)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard enabled, !unfinished.isEmpty else { return }

        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = hour
        comps.minute = 0
        guard let fireDate = Calendar.current.date(from: comps), fireDate > Date() else { return }

        let request = UNNotificationRequest(
            identifier: identifier,
            content: Self.nudgeContent(unfinished: unfinished),
            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        )
        do {
            try await center.add(request)
        } catch {
            Log.notifications.error("Nudge scheduling failed: \(error.localizedDescription)")
        }
    }

    func pendingRequests() async -> [UNNotificationRequest] {
        await center.pendingNotificationRequests()
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
