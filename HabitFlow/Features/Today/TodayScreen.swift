import SwiftUI
import HabitCore

/// Owns navigation and the "which logical day is it" decision; `TodayView` is recreated on rollover.
struct TodayScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var showEditor = false

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
