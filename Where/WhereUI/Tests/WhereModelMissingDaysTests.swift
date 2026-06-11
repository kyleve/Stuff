import Foundation
import Testing
import WhereCore
@testable import WhereUI

/// Covers the missing-day computation the banner / backfill read, and the
/// persistence of the reminder settings.
@MainActor
struct WhereModelMissingDaysTests {
    /// Build dates in the same calendar `WhereModel` uses (gregorian, current
    /// time zone), so the day keys line up regardless of the host machine.
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    private static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func ephemeralDefaults() -> UserDefaults {
        let suite = "test.WhereModelMissingDays.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeController() throws -> WhereController {
        try WhereController(
            store: SwiftDataStore.inMemory(),
            locationSource: ScriptedLocationSource(),
            reminderScheduler: NoopLoggingReminderScheduler(),
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
        let model = try WhereModel(
            controller: makeController(),
            report: report,
            selectedYear: 2026,
            now: { today },
        )

        // Jan 1 and Jan 3 are past gaps. Jan 5 (today) is still loggable, so it
        // isn't surfaced even though it's unlogged.
        #expect(model.missingDays.map(\.start) == [
            Self.day(2026, 1, 1),
            Self.day(2026, 1, 3),
        ])
        #expect(model.missingDayCount == 2)
        #expect(!model.missingDays.contains { $0.start == Self.day(2026, 1, 5) })
    }

    @Test func missingDaysAreEmptyWhenViewingAPastYear() throws {
        let today = Self.day(2026, 6, 1)
        let model = try WhereModel(
            controller: makeController(),
            report: YearReport(year: 2025, days: [], totals: [:]),
            selectedYear: 2025,
            now: { today },
        )

        #expect(model.missingDays.isEmpty)
        #expect(model.missingDayCount == 0)
    }

    @Test func reminderSettingsDefaultOnAndPersistAcrossModels() throws {
        let defaults = ephemeralDefaults()
        let model = try WhereModel(controller: makeController(), defaults: defaults)

        #expect(model.remindersEnabled)
        #expect(model.reminderTime == ReminderTime.defaultEvening)

        // Setting the key-path-bindable properties persists synchronously (the
        // reconcile they kick off runs against the no-op scheduler).
        model.remindersEnabled = false
        model.reminderTime = ReminderTime(hour: 7, minute: 30)
        #expect(!model.remindersEnabled)
        #expect(model.reminderTime == ReminderTime(hour: 7, minute: 30))

        // A fresh model sharing the same defaults reads back the saved values.
        let reloaded = try WhereModel(controller: makeController(), defaults: defaults)
        #expect(!reloaded.remindersEnabled)
        #expect(reloaded.reminderTime == ReminderTime(hour: 7, minute: 30))
    }
}
