import Foundation
import Testing
import WhereCore
import WhereTesting
import WhereUI

/// Covers `RemindersSettingsModel` — the Settings editing surface for the
/// reminder + daily-summary schedules. Setting a property persists to the shared
/// `WherePreferences` and reconciles against the (no-op) scheduler, so a fresh
/// model over the same preferences reads the saved values back.
@MainActor
struct RemindersSettingsModelTests {
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

    private func makeModel(preferences: WherePreferences) throws -> RemindersSettingsModel {
        try RemindersSettingsModel(services: makeServices(), preferences: preferences)
    }

    @Test func reminderSettingsDefaultOnAndPersistAcrossModels() throws {
        let preferences = makePreferences()
        let model = try makeModel(preferences: preferences)

        #expect(model.remindersEnabled)
        #expect(model.reminderTime == ReminderTime.defaultEvening)

        // Setting the key-path-bindable properties persists synchronously (the
        // reconcile they kick off runs against the no-op scheduler).
        model.remindersEnabled = false
        model.reminderTime = ReminderTime(hour: 7, minute: 30)
        #expect(!model.remindersEnabled)
        #expect(model.reminderTime == ReminderTime(hour: 7, minute: 30))

        // A fresh model sharing the same preferences reads back the saved values.
        let reloaded = try makeModel(preferences: preferences)
        #expect(!reloaded.remindersEnabled)
        #expect(reloaded.reminderTime == ReminderTime(hour: 7, minute: 30))
    }

    @Test func summarySettingsDefaultOnAndPersistAcrossModels() throws {
        let preferences = makePreferences()
        let model = try makeModel(preferences: preferences)

        #expect(model.summaryEnabled)
        #expect(model.summaryTime == ReminderTime.defaultMorning)

        model.summaryEnabled = false
        model.summaryTime = ReminderTime(hour: 9, minute: 15)
        #expect(!model.summaryEnabled)
        #expect(model.summaryTime == ReminderTime(hour: 9, minute: 15))

        // A fresh model sharing the same preferences reads back the saved values.
        let reloaded = try makeModel(preferences: preferences)
        #expect(!reloaded.summaryEnabled)
        #expect(reloaded.summaryTime == ReminderTime(hour: 9, minute: 15))
    }
}
