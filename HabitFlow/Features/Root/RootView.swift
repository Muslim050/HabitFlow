import SwiftUI
import HabitCore

struct RootView: View {
    @AppStorage(AppSettings.Key.hasCompletedOnboarding, store: AppSettings.store)
    private var hasCompletedOnboarding = false

    var body: some View {
        if hasCompletedOnboarding {
            MainTabView()
        } else {
            OnboardingView()
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            Tab("Today", systemImage: "circle.circle") {
                TodayScreen()
            }
            Tab("Settings", systemImage: "gearshape") {
                SettingsView()
            }
        }
    }
}
