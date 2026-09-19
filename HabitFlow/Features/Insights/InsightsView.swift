import SwiftUI
import HabitCore

struct InsightsView: View {
    @Environment(AppEnvironment.self) private var env

    private var analysis: AnalysisService { env.analysis }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ActivitySection()
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                } header: {
                    Text("Activity")
                }
                // No footer here: each range explains itself, and a fixed line underneath
                // contradicted whichever range was not the week.

                if !analysis.proposals.isEmpty {
                    Section {
                        ForEach(analysis.proposals) { proposal in
                            GoalProposalCard(proposal: proposal)
                        }
                    } header: {
                        Text("Goal suggestions")
                    } footer: {
                        Text("Goals follow what you actually do, so a habit stays challenging without becoming impossible.")
                    }
                }

                Section {
                    if analysis.insights.isEmpty {
                        ContentUnavailableView(
                            "Not enough history yet",
                            systemImage: "chart.line.uptrend.xyaxis",
                            description: Text("Keep going for a week or two. Patterns appear once there is enough data to be honest about.")
                        )
                    } else {
                        ForEach(analysis.insights) { insight in
                            InsightCard(presentation: InsightPresentation(
                                insight: insight,
                                habitName: analysis.habitName(insight.habitID),
                                relatedName: analysis.habitName(insight.relatedHabitID),
                                rule: analysis.habit(insight.habitID)?.rule
                            ))
                        }
                    }
                } header: {
                    Text("Patterns")
                } footer: {
                    if !analysis.insights.isEmpty {
                        Text("Observations come from your own history on this device. They show connections, not causes.")
                    }
                }
            }
            .navigationTitle("Insights")
            .refreshable { analysis.refresh() }
            .task { analysis.refreshIfNeeded() }
        }
    }
}

/// Actionable card: raise or lower a goal based on what actually happened.
struct GoalProposalCard: View {
    @Environment(AppEnvironment.self) private var env
    let proposal: GoalProposal

    private var habit: Habit? { env.analysis.habit(proposal.habitID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: proposal.direction == .increase ? "arrow.up.forward.circle.fill" : "arrow.down.forward.circle.fill")
                    .font(.title2)
                    .foregroundStyle(proposal.direction == .increase ? Color.green : Color.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(habit.map { "\($0.emoji) \($0.name)" } ?? "")
                        .font(.subheadline.weight(.semibold))
                    Text(headline).font(.footnote)
                }
            }
            Text(reason).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button {
                    env.analysis.apply(proposal)
                    env.habitDidChange(habit)
                } label: {
                    Text(proposal.direction == .increase ? "Raise goal" : "Lower goal")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button("Keep as is") { env.analysis.dismiss(proposal) }
                    .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 6)
    }

    private var headline: String {
        let from = ValueFormatting.value(proposal.currentTarget, unit: proposal.unitLabel)
        let to = ValueFormatting.value(proposal.proposedTarget, unit: proposal.unitLabel)
        return String(localized: "\(from) → \(to) \(ValueFormatting.unit(proposal.unitLabel))")
    }

    private var reason: String {
        let median = ValueFormatting.value(proposal.medianValue, unit: proposal.unitLabel)
        let rate = InsightPresentation.percent(proposal.completionRate)
        return proposal.direction == .increase
            ? String(localized: "Completed \(rate) of the last \(proposal.sampleDays) days, typically reaching \(median).")
            : String(localized: "Completed only \(rate) of the last \(proposal.sampleDays) days, typically reaching \(median).")
    }
}
