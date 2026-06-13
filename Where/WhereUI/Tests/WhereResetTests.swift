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
/// tracking, clears the preferences that gate onboarding, then re-drives the
/// launch back to its first-run state.
@MainActor
struct WhereResetTests {
    /// Owns every ephemeral suite this test creates and tears them down when
    /// the per-test suite instance is released (see `EphemeralDefaults`).
    private let defaultsStore = EphemeralDefaults()
    private func ephemeralDefaults() -> UserDefaults {
        defaultsStore.make("WhereReset")
    }

    /// A model with an injected controller (in-memory store, no-op schedulers)
    /// so the flow runs without touching real CoreLocation, the disk, or the
    /// notification center.
    private func makeModel(
        status: LocationAuthorizationStatus = .always,
        defaults: UserDefaults,
    ) throws -> WhereModel {
        let controller = try WhereController(
            store: SwiftDataStore.inMemory(),
            locationSource: ScriptedLocationSource(authorizationStatus: status),
            reminderScheduler: NoopLoggingReminderScheduler(),
            summaryScheduler: NoopDailySummaryScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
        )
        return WhereModel(controller: controller, defaults: defaults)
    }

    @Test func resetSequenceErasesThenClearsPreferences() throws {
        let model = try makeModel(defaults: ephemeralDefaults())
        let ids = WhereLaunch.resetSequence(for: model).steps.map(\.id)
        #expect(ids == ["erase-data", "reset-preferences"])
    }

    @Test func resetPreferencesRestoresFirstInstallDefaults() throws {
        let model = try makeModel(defaults: ephemeralDefaults())
        model.completeOnboarding()
        model.remindersEnabled = false
        model.summaryEnabled = false
        #expect(model.hasOnboarded)

        model.resetPreferences()

        // Removing the keys lets the default-valued getters report first-install
        // state again: onboarding returns and reminders/summary default back on.
        #expect(!model.hasOnboarded)
        #expect(model.remindersEnabled)
        #expect(model.summaryEnabled)
    }

    @Test func eraseAllDataClearsTheStoreAndStopsTracking() async throws {
        let model = try makeModel(status: .always, defaults: ephemeralDefaults())
        model.completeOnboarding()
        await model.start()
        #expect(model.isTracking) // .always authorization resumed GPS

        try await model.setManualDay(date: Date(), regions: [.california])
        #expect(model.trackedDayCount == 1)

        try await model.eraseAllData()
        #expect(!model.isTracking)
        #expect(model.trackedDayCount == 0)

        // The store really is empty, not just the in-memory report: a reload
        // from disk finds nothing.
        await model.refresh()
        #expect(model.trackedDayCount == 0)
    }

    @Test func resetReturnsToOnboardingWithDataErased() async throws {
        let model = try makeModel(status: .always, defaults: ephemeralDefaults())
        model.completeOnboarding()
        let launcher = WhereLaunch.makeLauncher(model: model, reason: .userForeground)
        await launcher.run()
        #expect(launcher.phase.isReady)

        try await model.setManualDay(date: Date(), regions: [.california])
        #expect(model.trackedDayCount == 1)

        // reset re-drives the launch, which parks on onboarding again (now that
        // hasOnboarded is cleared), so reset() doesn't return until onboarding
        // is resolved — drive it from a task and wait for the parked step.
        let task = Task { @MainActor in
            await launcher.reset(WhereLaunch.resetSequence(for: model))
        }
        try await waitUntil { launcher.phase.runningStepID == "onboarding" }

        // Teardown ran before the relaunch reached onboarding: data erased,
        // tracking stopped, and the onboarding gate reopened.
        #expect(!model.hasOnboarded)
        #expect(!model.isTracking)
        #expect(launcher.phase.runningBridge?.presentation != nil)

        launcher.phase.runningBridge?.complete()
        await task.value

        #expect(launcher.phase.isReady)
        // load-year reran against the now-empty store.
        #expect(model.trackedDayCount == 0)
    }

    @Test func resetFailureParksLauncherAndKeepsPreferences() async throws {
        // A teardown whose erase step throws parks the launcher in .failed on
        // that step and never reaches reset-preferences, so the onboarding flag
        // is preserved rather than stranding the user in onboarding atop
        // un-erased data.
        let model = try makeModel(defaults: ephemeralDefaults())
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
