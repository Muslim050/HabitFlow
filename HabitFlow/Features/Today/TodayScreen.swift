import SwiftUI
import HabitCore

/// Owns navigation and the "which logical day is it" decision; `TodayView` is recreated on rollover.
struct TodayScreen: View {
    @Environment(AppEnvironment.self) private var env
    /// Owned by the tab view so a deep link can open it from any tab.
    @Binding var showEditor: Bool

    var body: some View {
        NavigationStack {
            TodayView(dayKey: env.currentDayKey)
                .id(env.currentDayKey.raw)
                .navigationTitle("Today")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showEditor = true } label: { Label("Add habit", systemImage: "plus") }
                    }
                }
                .navigationDestination(for: Habit.self) { habit in
                    HabitDetailView(habit: habit)
                }
                .sheet(isPresented: $showEditor) {
                    HabitEditorView(habit: nil)
                }
        }
    }
}
