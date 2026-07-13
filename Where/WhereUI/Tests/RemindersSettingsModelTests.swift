import Foundation
import TestHostSupport
import Testing
@_spi(Testing) import WhereCore
import WhereUI

/// Covers `RemindersSettingsModel` — the Settings editing surface for the
/// reminder + daily-summary schedules. Setting a property persists to the shared
/// `WherePreferences` (so a fresh model over the same preferences reads the saved
/// values back) *and* reconciles the live schedule: spy schedulers confirm each
/// setter pushes the intent — enable (with an authorization prompt), disable, and
/// a time edit — down through the reconciler.
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
            issueAlertScheduler: NoopDataIssueAlertScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
        )
    }

    private func makeServices(
        reminderScheduler: any LoggingReminderScheduling,
        summaryScheduler: any DailySummaryScheduling,
        issueAlertScheduler: any DataIssueAlertScheduling = NoopDataIssueAlertScheduler(),
    ) throws -> WhereServices {
        try WhereServices(
            store: SwiftDataStore.inMemory(),
            locationSource: ScriptedLocationSource(),
            reminderScheduler: reminderScheduler,
            summaryScheduler: summaryScheduler,
            issueAlertScheduler: issueAlertScheduler,
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

    // MARK: - Setter reconciliation reaches the schedulers

    /// Enabling reminders prompts for authorization and reconciles the schedule
    /// on — the persistence round-trip above can't see that the setter actually
    /// drove the reconciler.
    @Test func enablingRemindersRequestsAuthorizationAndReconciles() async throws {
        let preferences = makePreferences()
        preferences.remindersEnabled = false
        let reminderSpy = SpyReminderScheduler()
        let services = try makeServices(
            reminderScheduler: reminderSpy,
            summaryScheduler: NoopDailySummaryScheduler(),
        )
        let model = RemindersSettingsModel(services: services, preferences: preferences)

        model.remindersEnabled = true

        await waitUntil { await reminderSpy.reconcileCount >= 1 }
        #expect(await reminderSpy.authorizationRequests >= 1)
        #expect(await reminderSpy.lastEnabled == true)
        #expect(await reminderSpy.lastReminderTime == ReminderTime.defaultEvening)
    }

    /// Disabling reconciles the schedule off and never prompts (disabling can't
    /// need permission).
    @Test func disablingRemindersReconcilesOffWithoutAuthorization() async throws {
        let preferences = makePreferences()
        let reminderSpy = SpyReminderScheduler()
        let services = try makeServices(
            reminderScheduler: reminderSpy,
            summaryScheduler: NoopDailySummaryScheduler(),
        )
        let model = RemindersSettingsModel(services: services, preferences: preferences)

        model.remindersEnabled = false

        await waitUntil { await reminderSpy.reconcileCount >= 1 }
        #expect(await reminderSpy.lastEnabled == false)
        #expect(await reminderSpy.authorizationRequests == 0)
    }

    /// Editing the time re-reconciles with the new time (still enabled).
    @Test func changingReminderTimeReconcilesWithTheNewTime() async throws {
        let preferences = makePreferences()
        let reminderSpy = SpyReminderScheduler()
        let services = try makeServices(
            reminderScheduler: reminderSpy,
            summaryScheduler: NoopDailySummaryScheduler(),
        )
        let model = RemindersSettingsModel(services: services, preferences: preferences)

        let newTime = ReminderTime(hour: 7, minute: 30)
        model.reminderTime = newTime

        await waitUntil { await reminderSpy.lastReminderTime == newTime }
        #expect(await reminderSpy.lastEnabled == true)
    }

    @Test func enablingSummaryRequestsAuthorizationAndReconciles() async throws {
        let preferences = makePreferences()
        preferences.summaryEnabled = false
        let summarySpy = SpyDailySummaryScheduler()
        let services = try makeServices(
            reminderScheduler: NoopLoggingReminderScheduler(),
            summaryScheduler: summarySpy,
        )
        let model = RemindersSettingsModel(services: services, preferences: preferences)

        model.summaryEnabled = true

        await waitUntil { await summarySpy.reconcileCount >= 1 }
        #expect(await summarySpy.authorizationRequests >= 1)
        #expect(await summarySpy.lastEnabled == true)
        #expect(await summarySpy.lastTime == ReminderTime.defaultMorning)
    }

    @Test func disablingSummaryReconcilesOffWithoutAuthorization() async throws {
        let preferences = makePreferences()
        let summarySpy = SpyDailySummaryScheduler()
        let services = try makeServices(
            reminderScheduler: NoopLoggingReminderScheduler(),
            summaryScheduler: summarySpy,
        )
        let model = RemindersSettingsModel(services: services, preferences: preferences)

        model.summaryEnabled = false

        await waitUntil { await summarySpy.reconcileCount >= 1 }
        #expect(await summarySpy.lastEnabled == false)
        #expect(await summarySpy.authorizationRequests == 0)
    }

    @Test func changingSummaryTimeReconcilesWithTheNewTime() async throws {
        let preferences = makePreferences()
        let summarySpy = SpyDailySummaryScheduler()
        let services = try makeServices(
            reminderScheduler: NoopLoggingReminderScheduler(),
            summaryScheduler: summarySpy,
        )
        let model = RemindersSettingsModel(services: services, preferences: preferences)

        let newTime = ReminderTime(hour: 9, minute: 15)
        model.summaryTime = newTime

        await waitUntil { await summarySpy.lastTime == newTime }
        #expect(await summarySpy.lastEnabled == true)
    }

    // MARK: - Issue alerts

    @Test func issueAlertsDefaultOnAndPersistAcrossModels() throws {
        let preferences = makePreferences()
        let model = try makeModel(preferences: preferences)

        #expect(model.issueAlertsEnabled)

        model.issueAlertsEnabled = false
        #expect(!model.issueAlertsEnabled)

        // A fresh model sharing the same preferences reads back the saved value.
        let reloaded = try makeModel(preferences: preferences)
        #expect(!reloaded.issueAlertsEnabled)
    }

    /// Enabling issue alerts prompts for authorization and reconciles the alert
    /// on; it also re-reconciles the reminder reconciler because the badge folds
    /// in the issue count.
    @Test func enablingIssueAlertsReconcilesAlertAndBadge() async throws {
        let preferences = makePreferences()
        preferences.issueAlertsEnabled = false
        let alertSpy = SpyDataIssueAlertScheduler()
        let reminderSpy = SpyReminderScheduler()
        let services = try makeServices(
            reminderScheduler: reminderSpy,
            summaryScheduler: NoopDailySummaryScheduler(),
            issueAlertScheduler: alertSpy,
        )
        let model = RemindersSettingsModel(services: services, preferences: preferences)

        model.issueAlertsEnabled = true

        // Enabling requests authorization and reconciles the alert (the empty
        // store has no issues yet, so the scheduler is reconciled *off* — the
        // observable proof the intent reached it is the auth prompt + reconcile).
        await waitUntil { await alertSpy.reconcileCount >= 1 }
        #expect(await alertSpy.authorizationRequests >= 1)
        // The reminder reconciler re-runs so the badge picks up the issue count.
        await waitUntil { await reminderSpy.reconcileCount >= 1 }
    }

    @Test func disablingIssueAlertsReconcilesOffWithoutAuthorization() async throws {
        let preferences = makePreferences()
        let alertSpy = SpyDataIssueAlertScheduler()
        let services = try makeServices(
            reminderScheduler: NoopLoggingReminderScheduler(),
            summaryScheduler: NoopDailySummaryScheduler(),
            issueAlertScheduler: alertSpy,
        )
        let model = RemindersSettingsModel(services: services, preferences: preferences)

        model.issueAlertsEnabled = false

        await waitUntil { await alertSpy.reconcileCount >= 1 }
        #expect(await alertSpy.lastEnabled == false)
        #expect(await alertSpy.authorizationRequests == 0)
    }

    /// The setters reconcile off an unstructured `Task`, so poll the (actor) spy
    /// rather than assuming the reconcile has landed by the next line.
    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ predicate: () async -> Bool,
    ) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if await predicate() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(await predicate(), "condition was not met before timeout")
    }
}

/// Records the calls `RemindersSettingsModel` funnels through the reminder
/// reconciler into its scheduler, so a setter's reconcile can be asserted
/// without touching `UNUserNotificationCenter`.
private actor SpyReminderScheduler: LoggingReminderScheduling {
    private(set) var authorizationRequests = 0
    private(set) var reconcileCount = 0
    private(set) var lastEnabled: Bool?
    private(set) var lastReminderTime: ReminderTime?

    func requestAuthorization() async -> Bool {
        authorizationRequests += 1
        return true
    }

    func isAuthorized() async -> Bool {
        true
    }

    func reconcile(
        badgeCount _: Int,
        scheduleDays _: [Date],
        reminderTime: ReminderTime,
        enabled: Bool,
    ) async {
        reconcileCount += 1
        lastReminderTime = reminderTime
        lastEnabled = enabled
    }
}

/// The daily-summary counterpart to `SpyReminderScheduler`.
private actor SpyDailySummaryScheduler: DailySummaryScheduling {
    private(set) var authorizationRequests = 0
    private(set) var reconcileCount = 0
    private(set) var lastEnabled: Bool?
    private(set) var lastTime: ReminderTime?

    func requestAuthorization() async -> Bool {
        authorizationRequests += 1
        return true
    }

    func isAuthorized() async -> Bool {
        true
    }

    func reconcile(enabled: Bool, time: ReminderTime, body _: String) async {
        reconcileCount += 1
        lastEnabled = enabled
        lastTime = time
    }
}

/// The issue-alert counterpart to `SpyReminderScheduler`.
private actor SpyDataIssueAlertScheduler: DataIssueAlertScheduling {
    private(set) var authorizationRequests = 0
    private(set) var reconcileCount = 0
    private(set) var lastEnabled: Bool?

    func requestAuthorization() async -> Bool {
        authorizationRequests += 1
        return true
    }

    func isAuthorized() async -> Bool {
        true
    }

    func reconcile(enabled: Bool, time _: ReminderTime, body _: String) async {
        reconcileCount += 1
        lastEnabled = enabled
    }
}
