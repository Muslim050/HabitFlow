import SwiftUI
import HabitCore

struct InsightsView: View {
    @Environment(AppEnvironment.self) private var env

    private var analysis: AnalysisService { env.analysis }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    topBar
                    RhythmHeroView(
                        insightCount: analysis.insights.count,
                        suggestionCount: analysis.proposals.count
                    )

                    HFSectionHeader(title: "Activity", detail: "Your history")
                        .padding(.top, 8)
                    ActivitySection()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .hfCard()

                    if !analysis.proposals.isEmpty {
                        HFSectionHeader(title: "Goal suggestions", detail: "Ready when you are")
                            .padding(.top, 8)
                        ForEach(analysis.proposals) { proposal in
                            GoalProposalCard(proposal: proposal)
                        }
                    }

                    if analysis.insights.isEmpty {
                        ContentUnavailableView(
                            "Not enough history yet",
                            systemImage: "chart.line.uptrend.xyaxis",
                            description: Text("Keep going for a week or two. Patterns appear once there is enough data to be honest about.")
                        )
                        .frame(maxWidth: .infinity)
                        .hfCard(padding: 26)
                    } else {
                        HFSectionHeader(title: "What helps", detail: "From your own history")
                            .padding(.top, 8)
                        ForEach(analysis.insights) { insight in
                            InsightCard(presentation: InsightPresentation(
                                insight: insight,
                                habitName: analysis.habitName(insight.habitID),
                                relatedName: analysis.habitName(insight.relatedHabitID),
                                rule: analysis.habit(insight.habitID)?.rule
                            ))
                        }
                    }
                    if !analysis.insights.isEmpty {
                        Text("Observations come from your own history on this device. They show connections, not causes.")
                            .font(.caption2)
                            .foregroundStyle(HFTheme.secondaryInk)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 112)
            }
            .background(HFTheme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { analysis.refresh() }
            .task { analysis.refreshIfNeeded() }
        }
    }

    private var topBar: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Your progress")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(HFTheme.secondaryInk)
                Text("Rhythm")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .tracking(-1.2)
                    .foregroundStyle(HFTheme.ink)
            }
            Spacer()
        }
        .padding(.bottom, 4)
    }
}

private struct RhythmHeroView: View {
    let insightCount: Int
    let suggestionCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("A calm view of your momentum")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(HFTheme.accent)
                    Text(heroTitle)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .tracking(-0.5)
                        .foregroundStyle(HFTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Image(systemName: "waveform.path.ecg")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(HFTheme.accent)
                    .frame(width: 52, height: 52)
                    .background(HFTheme.surface.opacity(0.76), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .stroke(HFTheme.accent.opacity(0.10), lineWidth: 1)
                    }
            }
            HStack(spacing: 10) {
                metric(value: insightCount, label: "Patterns")
                metric(value: suggestionCount, label: "Goal suggestions")
            }
        }
        .padding(20)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [HFTheme.blueSoft, HFTheme.surface],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                RhythmPulseShape()
                    .stroke(HFTheme.accent.opacity(0.075), style: StrokeStyle(lineWidth: 25, lineCap: .round, lineJoin: .round))
                    .offset(y: 23)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .allowsHitTesting(false)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(HFTheme.accent.opacity(0.10), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .shadow(color: HFTheme.ink.opacity(0.045), radius: 16, y: 7)
    }

    private func metric(value: Int, label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value, format: .number)
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(HFTheme.ink)
            Text(label)
                .font(.caption)
                .foregroundStyle(HFTheme.secondaryInk)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(HFTheme.surface.opacity(0.76), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(HFTheme.accent.opacity(0.08), lineWidth: 1)
        }
    }

    private var heroTitle: LocalizedStringKey {
        insightCount == 0 ? "Your rhythm is taking shape" : "Your patterns are becoming clearer"
    }
}

private struct RhythmPulseShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: -rect.width * 0.06, y: rect.height * 0.66))
        path.addLine(to: CGPoint(x: rect.width * 0.24, y: rect.height * 0.66))
        path.addLine(to: CGPoint(x: rect.width * 0.34, y: rect.height * 0.48))
        path.addLine(to: CGPoint(x: rect.width * 0.43, y: rect.height * 0.81))
        path.addLine(to: CGPoint(x: rect.width * 0.55, y: rect.height * 0.31))
        path.addLine(to: CGPoint(x: rect.width * 0.65, y: rect.height * 0.66))
        path.addLine(to: CGPoint(x: rect.width * 1.06, y: rect.height * 0.66))
        return path
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
                    .foregroundStyle(proposal.direction == .increase ? HFTheme.accent : HFTheme.orange)
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
                .tint(HFTheme.accent)
                Button("Keep as is") { env.analysis.dismiss(proposal) }
                    .buttonStyle(.bordered)
                    .tint(HFTheme.ink)
            }
        }
        .hfCard(color: proposal.direction == .increase ? HFTheme.sage : HFTheme.orangeSoft)
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
