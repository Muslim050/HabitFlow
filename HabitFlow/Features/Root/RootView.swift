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
    @Environment(AppEnvironment.self) private var env
    @State private var selection = Tabs.today
    @State private var showNewHabit = false

    enum Tabs { case today, insights, settings }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Today", systemImage: "circle.circle", value: Tabs.today) {
                TodayScreen(showEditor: $showNewHabit)
            }
            Tab("Insights", systemImage: "chart.line.uptrend.xyaxis", value: Tabs.insights) {
                InsightsView()
            }
            Tab("Settings", systemImage: "gearshape", value: Tabs.settings) {
                SettingsView()
            }
        }
        // The widget's "own habit" button can only hand the app a URL; the form lives here.
        .onChange(of: env.pendingDeepLink) { _, url in
            guard let url, url.host() == AppEnvironment.newHabitHost else { return }
            selection = .today
            showNewHabit = true
            env.consumeDeepLink()
        }
    }
}
