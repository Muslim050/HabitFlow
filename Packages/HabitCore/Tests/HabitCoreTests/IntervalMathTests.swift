import Foundation
import Testing
@testable import HabitCore

@Suite("IntervalMath")
struct IntervalMathTests {
    func interval(_ startHour: Double, _ endHour: Double) -> DateInterval {
        let base = Fixed.date(2026, 9, 11, 18)
        return DateInterval(start: base.addingTimeInterval(startHour * 3600), end: base.addingTimeInterval(endHour * 3600))
    }

    @Test func mergesOverlaps() {
        let merged = IntervalMath.merged([interval(0, 2), interval(1, 3), interval(5, 6), interval(6, 7)])
        #expect(merged.count == 2)
        #expect(merged[0].duration == 3 * 3600)
        #expect(merged[1].duration == 2 * 3600)
    }

    @Test func totalClipsToWindow() {
        // Sleep 22:00 → 06:30 with an overlapping Watch sample; window 18:00 → 14:00.
        let total = IntervalMath.totalDuration(
            of: [interval(4, 12.5), interval(5, 9)],
            clippedTo: interval(0, 20)
        )
        #expect(total == 8.5 * 3600)
        let clipped = IntervalMath.totalDuration(of: [interval(-2, 2)], clippedTo: interval(0, 20))
        #expect(clipped == 2 * 3600)
    }

    @Test func longestSingleStay() {
        let longest = IntervalMath.longestDuration(of: [interval(0, 0.5), interval(2, 3.5)], clippedTo: interval(0, 20))
        #expect(longest == 1.5 * 3600)
        #expect(IntervalMath.longestDuration(of: [], clippedTo: interval(0, 1)) == 0)
    }

    @Test func geofenceEvaluatorCountsOpenVisit() {
        let now = Fixed.date(2026, 9, 12, 12)
        let window = DateInterval(start: Fixed.date(2026, 9, 12, 4), end: Fixed.date(2026, 9, 13, 4))
        let rule = HabitRule.geofence(latitude: 0, longitude: 0, radius: 100, minDwellMinutes: 45, placeName: "Gym")
        let short = GeofenceEvaluator.snapshot(rule: rule, visits: [DateInterval(start: Fixed.date(2026, 9, 12, 11, 30), end: now)], window: window, now: now)
        #expect(short.value == 30)
        #expect(!short.isSatisfied)
        let long = GeofenceEvaluator.snapshot(rule: rule, visits: [DateInterval(start: Fixed.date(2026, 9, 12, 11), end: now)], window: window, now: now)
        #expect(long.value == 60)
        #expect(long.isSatisfied)
    }
}
