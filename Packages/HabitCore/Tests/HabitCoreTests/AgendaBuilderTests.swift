import Foundation
import Testing
@testable import HabitCore

@Suite("AgendaBuilder")
struct AgendaBuilderTests {
    let now = Fixed.date(2026, 9, 12, 14)

    func event(_ title: String, from: Int, to: Int, allDay: Bool = false) -> AgendaItem {
        AgendaItem(id: title, title: title, kind: .event,
                   start: allDay ? Fixed.date(2026, 9, 12, 0) : Fixed.date(2026, 9, 12, from),
                   end: allDay ? Fixed.date(2026, 9, 13, 0) : Fixed.date(2026, 9, 12, to),
                   isAllDay: allDay)
    }

    func reminder(_ title: String, at hour: Int?, done: Bool = false) -> AgendaItem {
        AgendaItem(id: title, title: title, kind: .reminder,
                   start: hour.map { Fixed.date(2026, 9, 12, $0) }, isCompleted: done)
    }

    @Test func keepsWhatIsStillAhead() {
        let items = [event("Standup", from: 9, to: 10), event("Review", from: 16, to: 17)]
        let arranged = AgendaBuilder.arrange(items, now: now)
        #expect(arranged.map(\.title) == ["Review"], "a meeting that ended is not on the strip")
    }

    @Test func dropsCompletedReminders() {
        let items = [reminder("Pay rent", at: 18), reminder("Call mum", at: 12, done: true)]
        #expect(AgendaBuilder.arrange(items, now: now).map(\.title) == ["Pay rent"])
    }

    @Test func overdueRemindersComeFirst() {
        let items = [
            event("Review", from: 16, to: 17),
            event("Conference", from: 0, to: 0, allDay: true),
            reminder("Pay rent", at: 11),      // overdue
            reminder("Someday", at: nil),
        ]
        #expect(AgendaBuilder.arrange(items, now: now).map(\.title)
                == ["Pay rent", "Conference", "Review", "Someday"])
    }

    @Test func timedItemsRunInOrder() {
        let items = [event("Late", from: 20, to: 21), event("Soon", from: 15, to: 16),
                     reminder("Mid", at: 17)]
        #expect(AgendaBuilder.arrange(items, now: now).map(\.title) == ["Soon", "Mid", "Late"])
    }

    @Test func allDayEventsSurviveTheWholeDay() {
        let items = [event("Holiday", from: 0, to: 0, allDay: true)]
        #expect(AgendaBuilder.arrange(items, now: Fixed.date(2026, 9, 12, 23)).count == 1)
    }

    @Test func limitAndOverflow() {
        let items = (1...9).map { reminder("R\($0)", at: 15 + $0 % 5) }
        let arranged = AgendaBuilder.arrange(items, now: now, limit: 4)
        #expect(arranged.count == 4)
        #expect(AgendaBuilder.overflow(items, now: now, limit: 4) == 5)
        #expect(AgendaBuilder.arrange(items, now: now, limit: 0).isEmpty)
    }

    @Test func overflowIgnoresWhatWasFilteredOut() {
        let items = [reminder("Done", at: 12, done: true), event("Past", from: 8, to: 9),
                     reminder("Live", at: 18)]
        #expect(AgendaBuilder.overflow(items, now: now, limit: 5) == 0)
    }

    @Test func overdueAndFinishedAreKindSpecific() {
        let pastEvent = event("Past", from: 8, to: 9)
        let pastReminder = reminder("Late", at: 8)
        #expect(pastEvent.hasFinished(now: now))
        #expect(!pastEvent.isOverdue(now: now), "an event that happened is not overdue")
        #expect(pastReminder.isOverdue(now: now))
        #expect(!pastReminder.hasFinished(now: now))
    }
}
