import UIKit
import UserNotifications

/// The single place where background wake paths reach the engine:
/// HealthKit observers, region monitoring and BGTaskScheduler are all (re)wired here at launch.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        BackgroundRefresh.register()
        let env = AppEnvironment.shared
        UNUserNotificationCenter.current().delegate = env.notifications
        env.handleLaunch(launchedForLocation: launchOptions?[.location] != nil)
        return true
    }
}
