import Foundation
import LifecycleKit
import Testing
import WhereCore
import WhereTesting
import WhereUI

private struct WaitTimeout: Error {}

/// Polls `predicate` on the main actor until it holds or the timeout elapses,
/// yielding to the launcher's drive task between checks.
@MainActor
private func waitUntil(
    timeout: Duration = .seconds(5),
    _ predicate: () -> Bool,
) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !predicate() {
        if ContinuousClock.now >= deadline { throw WaitTimeout() }
        try await Task.sleep(for: .milliseconds(1))
    }
}

/// Covers the `WhereLaunch.resetSequence` teardown the Settings "Erase all data
/// & reset" action runs through `LifecycleRunner.reset`: it wipes the store, stops
/// tracking, drops the session, clears the preferences that gate onboarding, then
/// re-drives the launch back to its first-run state.
@MainActor
struct WhereResetTests {
    private func makePreferences() -> WherePreferences {
        WherePreferences(store: InMemoryKeyValueStore())
    }

    private func makeServices(
        status: LocationAuthorizationStatus = .always,
    ) throws -> WhereServices {
        try WhereServices(
            store: SwiftDataStore.inMemory(),
            locationSource: ScriptedLocationSource(authorizationStatus: status),
            reminderScheduler: NoopLoggingReminderScheduler(),
            summaryScheduler: NoopDailySummaryScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
        )
    }

    /// A model with injected services (in-memory store, no-op schedulers)
    /// so the flow runs without touching real CoreLocation, the disk, or the
    /// notification center. The injected services build the session up front.
    private func makeModel(
        status: LocationAuthorizationStatus = .always,
        preferences: WherePreferences,
    ) throws -> WhereModel {
        try WhereModel(services: makeServices(status: status), preferences: preferences)
    }

    /// A model plus the scripted location source backing it, so a test can push
    /// authorization changes through the shared stream after the launch.
    private func makeModelWithSource(
        status: LocationAuthorizationStatus = .always,
        preferences: WherePreferences,
    ) throws -> (WhereModel, ScriptedLocationSource) {
        let source = ScriptedLocationSource(authorizationStatus: status)
        let services = try WhereServices(
            store: SwiftDataStore.inMemory(),
            locationSource: source,
            reminderScheduler: NoopLoggingReminderScheduler(),
            summaryScheduler: NoopDailySummaryScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
        )
        return (WhereModel(services: services, preferences: preferences), source)
    }

    @Test func resetSequenceErasesThenClearsPreferences() throws {
        let model = try makeModel(preferences: makePreferences())
        let ids = WhereLaunch.resetSequence(for: model).steps.map(\.id)
        #expect(ids == [LaunchStepID.eraseData, .resetPreferences].map { AnyHashable($0) })
    }

    @Test func resetPreferencesRestoresFirstInstallDefaults() throws {
        let preferences = makePreferences()
        let model = try makeModel(preferences: preferences)
        model.completeOnboarding()
        // Turn the reminder/summary schedules off through the shared preferences
        // (the editing surface, `RemindersSettingsModel`, writes here).
        preferences.remindersEnabled = false
        preferences.summaryEnabled = false
        #expect(model.hasOnboarded)

        model.resetPreferences()

        // Removing the keys lets the default-valued getters report first-install
        // state again: onboarding returns and reminders/summary default back on.
        #expect(!model.hasOnboarded)
        #expect(preferences.remindersEnabled)
        #expect(preferences.summaryEnabled)
    }

    @Test func eraseAllDataClearsTheStoreAndStopsTracking() async throws {
        let preferences = makePreferences()
        let services = try makeServices(status: .always)
        let model = WhereModel(services: services, preferences: preferences)
        model.completeOnboarding()
        let session = try #require(model.session)
        // The scene's report model shares the coordinator's services (its store).
        let report = YearReportModel(services: services, preferences: preferences)
        await session.start()
        #expect(session.isTracking) // .always authorization resumed GPS

        try await report.setManualDay(date: Date(), regions: [.california])
        await report.refresh()
        #expect(report.trackedDayCount == 1)

        try await model.eraseAllData()
        #expect(!session.isTracking)

        // The store really is empty, not just the in-memory report: a reload
        // from disk finds nothing.
        await report.refresh()
        #expect(report.trackedDayCount == 0)
    }

    @Test func endSessionDropsTheSessionAndRelaunchRebuildsIt() async throws {
        let model = try makeModel(status: .always, preferences: makePreferences())
        model.completeOnboarding()
        let original = try #require(model.session)

        model.endSession()
        #expect(model.session == nil)

        // The re-driven launch rebuilds a fresh session from the retained
        // (still-open) services rather than reopening the store.
        let launcher = WhereLaunch.makeLauncher(model: model, reason: .userForeground)
        await launcher.run()
        #expect(launcher.phase.isReady)
        let rebuilt = try #require(model.session)
        #expect(rebuilt !== original)
    }

    @Test func authorizationChangeReachesTheRebuiltSessionAfterReset() async throws {
        // Regression: after a reset, a live authorization change must reach the
        // rebuilt session. This guards two things together — the source fans
        // `authorizationUpdates` out per subscriber (`AuthorizationStatusBroadcaster`)
        // so the rebuilt session gets its own stream, and `WhereSession.deinit`
        // cancels the dropped session's observer so it stops competing for it.
        let preferences = makePreferences()
        let (model, source) = try makeModelWithSource(status: .always, preferences: preferences)
        model.completeOnboarding()
        weak var weakOriginal = model.session

        let launcher = WhereLaunch.makeLauncher(model: model, reason: .userForeground)
        await launcher.run()
        #expect(launcher.phase.isReady)

        // Reset re-drives into onboarding (hasOnboarded cleared); complete it so
        // the relaunch rebuilds a fresh session and reaches .ready.
        let task = Task { @MainActor in
            await launcher.teardown(WhereLaunch.resetSequence(for: model))
        }
        try await waitUntil { launcher.phase.isRunning(LaunchStepID.onboarding) }
        launcher.phase.runningBridge?.complete()
        await task.value
        #expect(launcher.phase.isReady)

        // The original session was torn down, so only the rebuilt session is left
        // observing the shared stream.
        #expect(weakOriginal == nil)
        let rebuilt = try #require(model.session)
        #expect(rebuilt.authorizationStatus == .always)

        // A Settings-app authorization change arrives through the shared stream
        // and reaches the rebuilt session rather than the defunct original's
        // observer.
        source.emitAuthorization(.denied)
        try await waitUntil { rebuilt.authorizationStatus == .denied }
    }

    @Test func resetReturnsToOnboardingWithDataErased() async throws {
        let preferences = makePreferences()
        let services = try makeServices(status: .always)
        let model = WhereModel(services: services, preferences: preferences)
        model.completeOnboarding()
        let launcher = WhereLaunch.makeLauncher(model: model, reason: .userForeground)
        await launcher.run()
        #expect(launcher.phase.isReady)

        let session = try #require(model.session)
        let report = YearReportModel(services: services, preferences: preferences)
        try await report.setManualDay(date: Date(), regions: [.california])
        await report.refresh()
        #expect(report.trackedDayCount == 1)

        // reset re-drives the launch, which parks on onboarding again (now that
        // hasOnboarded is cleared), so reset() doesn't return until onboarding
        // is resolved — drive it from a task and wait for the parked step.
        let task = Task { @MainActor in
            await launcher.teardown(WhereLaunch.resetSequence(for: model))
        }
        try await waitUntil { launcher.phase.isRunning(LaunchStepID.onboarding) }

        // Teardown ran before the relaunch reached onboarding: data erased, the
        // session dropped + rebuilt, and the onboarding gate reopened.
        #expect(!model.hasOnboarded)
        let rebuilt = try #require(model.session)
        #expect(rebuilt !== session)
        #expect(!rebuilt.isTracking)
        #expect(launcher.phase.runningBridge?.presentation != nil)

        launcher.phase.runningBridge?.complete()
        await task.value

        #expect(launcher.phase.isReady)
        // The store was wiped: a fresh report read against it finds nothing.
        await report.refresh()
        #expect(report.trackedDayCount == 0)
    }

    @Test func resetDropsSessionClearsPreferencesAndReturnsToOnboarding() async throws {
        // The end-to-end reset cycle: a user who has onboarded, turned the
        // reminders/summary off, and logged a day runs "Erase all data & reset".
        let preferences = makePreferences()
        let services = try makeServices(status: .always)
        let model = WhereModel(services: services, preferences: preferences)
        let original = try #require(model.session)
        model.completeOnboarding()
        preferences.remindersEnabled = false
        preferences.summaryEnabled = false

        let launcher = WhereLaunch.makeLauncher(model: model, reason: .userForeground)
        await launcher.run()
        let report = YearReportModel(services: services, preferences: preferences)
        try await report.setManualDay(date: Date(), regions: [.california])
        await report.refresh()
        #expect(report.trackedDayCount == 1)

        // Drive the reset and finish the onboarding it re-drives into.
        let task = Task { @MainActor in
            await launcher.teardown(WhereLaunch.resetSequence(for: model))
        }
        try await waitUntil { launcher.phase.isRunning(LaunchStepID.onboarding) }

        // Mid-relaunch: the session was dropped and rebuilt fresh, and the
        // preferences were cleared (onboarding gate reopened; the reminder/summary
        // schedules default back on) — not the off state above.
        let rebuilt = try #require(model.session)
        #expect(rebuilt !== original)
        #expect(!model.hasOnboarded)
        #expect(preferences.remindersEnabled)
        #expect(preferences.summaryEnabled)

        launcher.phase.runningBridge?.complete()
        await task.value
        #expect(launcher.phase.isReady)
        // The store was wiped: a fresh report read against it is empty.
        await report.refresh()
        #expect(report.trackedDayCount == 0)
    }

    @Test func resetFailureParksLauncherAndKeepsPreferences() async throws {
        // A teardown whose erase step throws parks the launcher in .failed on
        // that step and never reaches reset-preferences, so the onboarding flag
        // is preserved rather than stranding the user in onboarding atop
        // un-erased data.
        let model = try makeModel(preferences: makePreferences())
        model.completeOnboarding()

        let failing = LifecycleSteps {
            LifecycleStep.work(LaunchStepID.eraseData) { _ in
                throw CocoaError(.fileWriteUnknown)
            }
            LifecycleStep.work(LaunchStepID.resetPreferences) { _ in
                model.resetPreferences()
            }
        }
        let launcher = WhereLaunch.makeLauncher(model: model, reason: .userForeground)
        await launcher.run()
        #expect(launcher.phase.isReady)

        await launcher.teardown(failing)
        #expect(launcher.phase.failed(at: LaunchStepID.eraseData))
        #expect(model.hasOnboarded) // reset-preferences never ran
    }
}
