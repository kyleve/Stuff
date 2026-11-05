import Foundation
import Testing
@testable import WhereCore

struct EveningReminderTests {
    @Test func combinedBodyIncludesEachEnabledConcern() {
        let reminder = EveningReminder(
            day: CalendarDay(year: 2026, month: 1, day: 5),
            remindsToLogDay: true,
            missingDayCount: 2,
            issueCount: 3,
        )
        #expect(reminder.body.contains("before the day ends"))
        #expect(reminder.body.contains("2 earlier days need history"))
        #expect(reminder.body.contains("3 issues to resolve"))
        #expect(reminder.body.contains("%") == false)
    }

    @Test func issueOnlyBodyDoesNotAskForAnotherRecording() {
        let reminder = EveningReminder(
            day: CalendarDay(year: 2026, month: 1, day: 5),
            remindsToLogDay: false,
            missingDayCount: 0,
            issueCount: 1,
        )
        #expect(reminder.hasWork)
        #expect(reminder.body == "1 issue to resolve")
    }

    @Test func emptyWorkHasNoBodyOrNotification() {
        let reminder = EveningReminder(
            day: CalendarDay(year: 2026, month: 1, day: 5),
            remindsToLogDay: false,
            missingDayCount: 0,
            issueCount: 0,
        )
        #expect(reminder.hasWork == false)
        #expect(reminder.body.isEmpty)
    }
}
