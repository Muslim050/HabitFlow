import Foundation
import Testing
import HabitCore
@testable import HabitFlow

/// The orchestration lives in `HabitCore.AnalysisEngine` and is tested there.
/// Here we only check how an insight is turned into words and numbers.
@Suite("Insight presentation")
struct InsightPresentationTests {
    @Test func formatsPercentagesAndTimes() {
        #expect(InsightPresentation.percent(0.865) == "87%")
        #expect(InsightPresentation.percent(0) == "0%")
        #expect(InsightPresentation.percent(1) == "100%")
        #expect(InsightPresentation.time(8.25) == "08:15")
        #expect(InsightPresentation.time(0) == "00:00")
        #expect(InsightPresentation.time(23.99) == "23:59")
        #expect(InsightPresentation.time(24) == "00:00", "wraps instead of printing 24:00")
    }

    @Test(arguments: [Insight.Kind.weeklyTrend, .weakWeekday, .pairing, .nearMiss, .typicalTime, .goalChanged])
    func everyKindProducesText(kind: Insight.Kind) {
        let insight = Insight(kind: kind, habitID: UUID(), relatedHabitID: UUID(), priority: 1,
                              primaryValue: kind == .typicalTime ? 8.5 : 0.8,
                              secondaryValue: 0.3, sampleDays: 20, unitLabel: "steps")
        let presentation = InsightPresentation(insight: insight, habitName: "Walk", relatedName: "Sleep", rule: nil)
        #expect(!presentation.message.isEmpty)
        #expect(!presentation.icon.isEmpty)
        #expect(presentation.title == "Walk")
    }

    @Test func trendWordingFollowsDirection() {
        let up = Insight(kind: .weeklyTrend, priority: 1, primaryValue: 0.9, secondaryValue: 0.4, sampleDays: 14)
        let down = Insight(kind: .weeklyTrend, priority: 1, primaryValue: 0.4, secondaryValue: 0.9, sampleDays: 14)
        let upText = InsightPresentation(insight: up, habitName: "Walk", relatedName: "", rule: nil)
        let downText = InsightPresentation(insight: down, habitName: "Walk", relatedName: "", rule: nil)
        #expect(upText.icon == "arrow.up.right")
        #expect(downText.icon == "arrow.down.right")
        #expect(upText.message != downText.message)
    }
}
