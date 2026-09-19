import Foundation
import Testing
@testable import HabitCore

/// The point of this store is one distinction: a source that answered with nothing versus a
/// source that was never heard from. Everything else here guards that it survives a round trip.
@Suite("SourceHealth")
struct SourceHealthTests {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "SourceHealthTests-\(UUID().uuidString)")!
    }

    @Test func nothingRecordedReadsAsNeverHeardFrom() {
        let store = defaults()
        let report = SourceHealth.report(for: .healthQuantity, defaults: store)
        #expect(!report.hasEverDelivered)
        #expect(!report.hasEverRead)
        #expect(report.lastValue == nil)
    }

    @Test func aReadOfZeroIsNotTheSameAsNoRead() {
        let store = defaults()
        SourceHealth.recordRead(.healthQuantity, value: 0, at: Fixed.date(2026, 9, 19, 10, 0), defaults: store)

        let report = SourceHealth.report(for: .healthQuantity, defaults: store)
        #expect(report.hasEverRead, "the source did answer")
        #expect(report.lastValue == 0, "and the answer was nothing")
        #expect(!report.hasEverDelivered, "but it never pushed anything at us")
    }

    @Test func kindsAreKeptApart() {
        let store = defaults()
        SourceHealth.recordDelivery(.geofence, at: Fixed.date(2026, 9, 19, 9, 0), defaults: store)
        SourceHealth.recordRead(.healthSleep, value: 7.5, at: Fixed.date(2026, 9, 19, 10, 0), defaults: store)

        #expect(SourceHealth.report(for: .geofence, defaults: store).hasEverDelivered)
        #expect(!SourceHealth.report(for: .geofence, defaults: store).hasEverRead)
        #expect(SourceHealth.report(for: .healthSleep, defaults: store).lastValue == 7.5)
        #expect(!SourceHealth.report(for: .healthSleep, defaults: store).hasEverDelivered)
    }

    @Test func aLaterReadClearsAnEarlierError() {
        let store = defaults()
        SourceHealth.recordError(.healthWorkout, "Not authorized", at: Fixed.date(2026, 9, 19, 9, 0), defaults: store)
        #expect(SourceHealth.report(for: .healthWorkout, defaults: store).lastError == "Not authorized")

        SourceHealth.recordRead(.healthWorkout, value: 35, at: Fixed.date(2026, 9, 19, 10, 0), defaults: store)
        let report = SourceHealth.report(for: .healthWorkout, defaults: store)
        #expect(report.lastError == nil, "a source that answered is no longer failing")
        #expect(report.lastErrorAt != nil, "but when it last failed is still worth keeping")
    }

    @Test func recordsSurviveBeingWrittenOneAtATime() {
        let store = defaults()
        SourceHealth.recordDelivery(.healthQuantity, at: Fixed.date(2026, 9, 19, 8, 0), defaults: store)
        SourceHealth.recordRead(.healthQuantity, value: 9000, at: Fixed.date(2026, 9, 19, 9, 0), defaults: store)

        let report = SourceHealth.report(for: .healthQuantity, defaults: store)
        #expect(report.lastDeliveryAt == Fixed.date(2026, 9, 19, 8, 0), "the earlier write is not lost")
        #expect(report.lastValue == 9000)
    }
}
