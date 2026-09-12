import SwiftUI
import HabitCore

struct OnboardingView: View {
    @Environment(AppEnvironment.self) private var env
    @AppStorage(AppSettings.Key.hasCompletedOnboarding, store: AppSettings.store)
    private var hasCompletedOnboarding = false
    @State private var page = 0
    @State private var healthRequested = false
    @State private var requestingHealth = false

    var body: some View {
        VStack {
            TabView(selection: $page) {
                OnboardingPage(
                    symbol: "lock.shield",
                    title: "Habits that complete themselves",
                    text: "HabitFlow watches Health and the places you choose, and ticks habits off for you. Everything is processed on this iPhone. No account, no servers."
                ) {
                    Button("Continue") { withAnimation { page = 1 } }
                        .buttonStyle(.borderedProminent)
                }
                .tag(0)

                OnboardingPage(
                    symbol: "heart.text.square",
                    title: "Connect Health",
                    text: env.healthKit.isAvailable
                        ? "Steps, sleep, workouts, mindful minutes, water and active energy can complete habits automatically. You choose what to share on the next screen."
                        : "Health is not available on this device. You can still use manual and place-based habits."
                ) {
                    if env.healthKit.isAvailable {
                        Button(healthRequested ? "Continue" : "Allow Health access") {
                            if healthRequested { withAnimation { page = 2 } } else { requestHealth() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(requestingHealth)
                        Button("Not now") { withAnimation { page = 2 } }.buttonStyle(.borderless)
                    } else {
                        Button("Continue") { withAnimation { page = 2 } }.buttonStyle(.borderedProminent)
                    }
                }
                .tag(1)

                OnboardingPage(
                    symbol: "mappin.and.ellipse",
                    title: "Places (optional)",
                    text: "Add a place habit like “Gym, 45 min” and HabitFlow marks it done when you actually stay there. You can set this up later when you create the habit."
                ) {
                    Button("Enable location") {
                        env.location.requestWhenInUseAuthorization()
                        finish()
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Skip") { finish() }.buttonStyle(.borderless)
                }
                .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
        }
    }

    private func requestHealth() {
        requestingHealth = true
        Task {
            do { try await env.healthKit.requestAllReadAuthorization() } catch {
                Log.health.error("Onboarding Health auth: \(error.localizedDescription)")
            }
            requestingHealth = false
            healthRequested = true
            withAnimation { page = 2 }
        }
    }

    private func finish() {
        Task {
            _ = await env.notifications.requestAuthorization()
            hasCompletedOnboarding = true
        }
    }
}

struct OnboardingPage<Actions: View>: View {
    let symbol: String
    let title: String
    let text: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)
            Text(title).font(.title.bold()).multilineTextAlignment(.center)
            Text(text).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
            VStack(spacing: 12) { actions() }
                .padding(.bottom, 48)
        }
        .padding(.horizontal, 32)
    }
}
