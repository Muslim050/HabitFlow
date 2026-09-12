import SwiftUI
import HabitCore

@main
struct HabitFlowApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    private let env = AppEnvironment.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(env)
                .modelContainer(env.container)
                .onOpenURL { url in env.handleDeepLink(url) }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: env.startForegroundSession()
            case .background: env.endForegroundSession()
            default: break
            }
        }
    }
}
