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

    @Test func resetSequenceErasesThenClearsPreferences() throws {
        let model = try makeModel(preferences: makePreferences())
        let ids = WhereLaunch.resetSequence(for: model).steps.map(\.id)
        #expect(ids == ["erase-data", "reset-preferences"])
    }

    @Test func resetPreferencesRestoresFirstInstallDefaults() throws {
        let preferences = makePreferences()
        let model = try makeModel(preferences: preferences)
        let session = try #require(model.session)
        model.completeOnboarding()
        session.remindersEnabled = false
        session.summaryEnabled = false
        #expect(model.hasOnboarded)

        model.resetPreferences()

        // Removing the keys lets the default-valued getters report first-install
        // state again: onboarding returns and reminders/summary default back on.
        #expect(!model.hasOnboarded)
        // A fresh session re-reads the now-cleared preferences and sees the
        // restored defaults (the live session caches its values, so the reset
        // is observed by the rebuilt session the relaunch creates).
        let reloaded = try WhereSession(services: makeServices(), preferences: preferences)
        #expect(reloaded.remindersEnabled)
        #expect(reloaded.summaryEnabled)
    }

    @Test func eraseAllDataClearsTheStoreAndStopsTracking() async throws {
        let model = try makeModel(status: .always, preferences: makePreferences())
        model.completeOnboarding()
        let session = try #require(model.session)
        await session.start()
        #expect(session.isTracking) // .always authorization resumed GPS

        try await session.setManualDay(date: Date(), regions: [.california])
        #expect(session.trackedDayCount == 1)

        try await model.eraseAllData()
        #expect(!session.isTracking)
        #expect(session.trackedDayCount == 0)

        // The store really is empty, not just the in-memory report: a reload
        // from disk finds nothing.
        await session.refresh()
        #expect(session.trackedDayCount == 0)
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

    @Test func resetReturnsToOnboardingWithDataErased() async throws {
        let model = try makeModel(status: .always, preferences: makePreferences())
        model.completeOnboarding()
        let launcher = WhereLaunch.makeLauncher(model: model, reason: .userForeground)
        await launcher.run()
        #expect(launcher.phase.isReady)

        let session = try #require(model.session)
        try await session.setManualDay(date: Date(), regions: [.california])
        #expect(session.trackedDayCount == 1)

        // reset re-drives the launch, which parks on onboarding again (now that
        // hasOnboarded is cleared), so reset() doesn't return until onboarding
        // is resolved — drive it from a task and wait for the parked step.
        let task = Task { @MainActor in
            await launcher.reset(WhereLaunch.resetSequence(for: model))
        }
        try await waitUntil { launcher.phase.runningStepID == "onboarding" }

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
        // load-year reran against the now-empty store.
        #expect(model.session?.trackedDayCount == 0)
    }

    @Test func resetFailureParksLauncherAndKeepsPreferences() async throws {
        // A teardown whose erase step throws parks the launcher in .failed on
        // that step and never reaches reset-preferences, so the onboarding flag
        // is preserved rather than stranding the user in onboarding atop
        // un-erased data.
        let model = try makeModel(preferences: makePreferences())
        model.completeOnboarding()

        let failing = LifecycleSteps {
            LifecycleStep.work("erase-data") { _ in throw CocoaError(.fileWriteUnknown) }
            LifecycleStep.work("reset-preferences") { _ in model.resetPreferences() }
        }
        let launcher = WhereLaunch.makeLauncher(model: model, reason: .userForeground)
        await launcher.run()
        #expect(launcher.phase.isReady)

        await launcher.reset(failing)
        #expect(launcher.phase.failure?.stepID == "erase-data")
        #expect(model.hasOnboarded) // reset-preferences never ran
    }
}
