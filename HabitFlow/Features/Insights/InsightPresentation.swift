import Foundation
import SwiftUI
import HabitCore

/// Turns an `Insight` into words. Wording stays associative ("more often on days when"),
/// never causal, because completion history cannot support a causal claim.
struct InsightPresentation {
    var icon: String
    var tint: Color
    var title: String
    var message: String
    var footnote: String

    static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    static func time(_ hour: Double) -> String {
        let total = Int((hour * 60).rounded())
        return String(format: "%02d:%02d", (total / 60) % 24, total % 60)
    }

    static func weekdayName(_ weekday: Int) -> String {
        let symbols = Calendar.current.standaloneWeekdaySymbols
        let index = min(max(weekday - 1, 0), symbols.count - 1)
        return symbols[index].localizedCapitalized
    }

    init(insight: Insight, habitName: String, relatedName: String, rule: HabitRule?) {
        let sample = String(localized: "Based on \(insight.sampleDays) days")
        switch insight.kind {
        case .weeklyTrend:
            let improving = insight.primaryValue >= insight.secondaryValue
            icon = improving ? "arrow.up.right" : "arrow.down.right"
            tint = improving ? .green : .orange
            title = habitName
            message = improving
                ? String(localized: "Better this week: \(Self.percent(insight.primaryValue)) against \(Self.percent(insight.secondaryValue)) last week")
                : String(localized: "Weaker this week: \(Self.percent(insight.primaryValue)) against \(Self.percent(insight.secondaryValue)) last week")
            footnote = sample

        case .weakWeekday:
            icon = "calendar.badge.exclamationmark"
            tint = .orange
            title = habitName
            message = String(localized: "\(Self.weekdayName(Int(insight.primaryValue))) is the weakest day: \(Self.percent(insight.secondaryValue)) completed")
            footnote = String(localized: "Based on \(insight.sampleDays) such days")

        case .pairing:
            icon = "link"
            tint = .blue
            title = habitName
            message = String(localized: "Completed more often on days when “\(relatedName)” is done: \(Self.percent(insight.primaryValue)) against \(Self.percent(insight.secondaryValue))")
            footnote = String(localized: "A connection, not a cause. Based on \(insight.sampleDays) days")

        case .nearMiss:
            icon = "target"
            tint = .purple
            title = habitName
            message = String(localized: "You almost reach it: \(Self.percent(insight.primaryValue)) of the goal on a typical day, but it counted \(Self.percent(insight.secondaryValue)) of days")
            footnote = String(localized: "A slightly lower goal would make this a streak")

        case .typicalTime:
            icon = "clock"
            tint = .teal
            title = habitName
            message = String(localized: "Usually done around \(Self.time(insight.primaryValue))")
            footnote = sample

        case .goalChanged:
            icon = "wand.and.stars"
            tint = .indigo
            title = habitName
            let target = ValueFormatting.value(insight.primaryValue, unit: insight.unitLabel)
            message = String(localized: "Goal adjusted automatically: now \(target) \(ValueFormatting.unit(insight.unitLabel))")
            footnote = String(localized: "You can change it in the habit's settings")
        }
        _ = rule
    }
}

struct InsightCard: View {
    let presentation: InsightPresentation

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: presentation.icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(presentation.tint)
                .frame(width: 34, height: 34)
                .background(HFTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                Text(presentation.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HFTheme.ink)
                Text(presentation.message)
                    .font(.footnote)
                    .foregroundStyle(HFTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(presentation.footnote)
                    .font(.caption2)
                    .foregroundStyle(HFTheme.secondaryInk)
            }
            Spacer(minLength: 0)
        }
        .hfCard(color: presentation.tint.opacity(0.09))
    }
}
