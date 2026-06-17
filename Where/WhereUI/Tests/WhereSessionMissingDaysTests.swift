import Foundation
import Testing
import WhereCore
import WhereTesting
@testable import WhereUI

/// Covers the missing-day computation the banner / backfill read, and the
/// persistence of the reminder and daily-summary settings.
@MainActor
struct WhereSessionMissingDaysTests {
    /// Build dates in the same calendar `WhereSession` uses (gregorian, current
    /// time zone), so the day keys line up regardless of the host machine.
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    private static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func makePreferences() -> WherePreferences {
        WherePreferences(store: InMemoryKeyValueStore())
    }

    private func makeServices() throws -> WhereServices {
        try WhereServices(
            store: SwiftDataStore.inMemory(),
            locationSource: ScriptedLocationSource(),
            reminderScheduler: NoopLoggingReminderScheduler(),
            summaryScheduler: NoopDailySummaryScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
        )
    }

    @Test func missingDaysSurfacePastGapsAndExcludeToday() throws {
        let today = Self.day(2026, 1, 5)
        let present = [Self.day(2026, 1, 2), Self.day(2026, 1, 4)]
        let report = YearReport(
            year: 2026,
            days: present.map { DayPresence(date: $0, regions: [.california]) },
            totals: [.california: present.count],
        )
        let session = try WhereSession(
            services: makeServices(),
            report: report,
            selectedYear: 2026,
            now: { today },
        )

        // Jan 1 and Jan 3 are past gaps. Jan 5 (today) is still loggable, so it
        // isn't surfaced even though it's unlogged.
        #expect(session.missingDays.map(\.start) == [
            Self.day(2026, 1, 1),
            Self.day(2026, 1, 3),
        ])
        #expect(session.missingDayCount == 2)
        #expect(!session.missingDays.contains { $0.start == Self.day(2026, 1, 5) })
    }

    @Test func missingDaysAreEmptyWhenViewingAPastYear() throws {
        let today = Self.day(2026, 6, 1)
        let session = try WhereSession(
            services: makeServices(),
            report: YearReport(year: 2025, days: [], totals: [:]),
            selectedYear: 2025,
            now: { today },
        )

        #expect(session.missingDays.isEmpty)
        #expect(session.missingDayCount == 0)
    }

    @Test func reminderSettingsDefaultOnAndPersistAcrossSessions() throws {
        let preferences = makePreferences()
        let session = try WhereSession(services: makeServices(), preferences: preferences)

        #expect(session.remindersEnabled)
        #expect(session.reminderTime == ReminderTime.defaultEvening)

        // Setting the key-path-bindable properties persists synchronously (the
        // reconcile they kick off runs against the no-op scheduler).
        session.remindersEnabled = false
        session.reminderTime = ReminderTime(hour: 7, minute: 30)
        #expect(!session.remindersEnabled)
        #expect(session.reminderTime == ReminderTime(hour: 7, minute: 30))

        // A fresh session sharing the same preferences reads back the saved values.
        let reloaded = try WhereSession(services: makeServices(), preferences: preferences)
        #expect(!reloaded.remindersEnabled)
        #expect(reloaded.reminderTime == ReminderTime(hour: 7, minute: 30))
    }

    @Test func summarySettingsDefaultOnAndPersistAcrossSessions() throws {
        let preferences = makePreferences()
        let session = try WhereSession(services: makeServices(), preferences: preferences)

        #expect(session.summaryEnabled)
        #expect(session.summaryTime == ReminderTime.defaultMorning)

        session.summaryEnabled = false
        session.summaryTime = ReminderTime(hour: 9, minute: 15)
        #expect(!session.summaryEnabled)
        #expect(session.summaryTime == ReminderTime(hour: 9, minute: 15))

        // A fresh session sharing the same preferences reads back the saved values.
        let reloaded = try WhereSession(services: makeServices(), preferences: preferences)
        #expect(!reloaded.summaryEnabled)
        #expect(reloaded.summaryTime == ReminderTime(hour: 9, minute: 15))
    }
}
