import Foundation
import LifecycleKit
import SwiftData
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

/// Covers the `WhereLaunch` sequence the app drives at startup: the step order
/// (parity with `WhereModel.start()`), the onboarding gate, the headless
/// background path, and the migration UI prediction.
@MainActor
struct WhereLaunchTests {
    private func ephemeralDefaults(_ label: String = "WhereLaunch") -> UserDefaults {
        let suite = "test.\(label).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// A model with an injected controller (in-memory store, no-op schedulers)
    /// so the launch sequence runs without touching real CoreLocation, the
    /// disk, or the notification center.
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

    @Test func sequenceStepsRunInStartParityOrder() throws {
        // The work steps mirror WhereModel.start()'s order; the only insertions
        // are open-store's migration presentation and the onboarding gate.
        let model = try makeModel(defaults: ephemeralDefaults())
        let ids = WhereLaunch.sequence(for: model).steps.map(\.id)
        #expect(ids == [
            "open-store",
            "onboarding",
            "sync-auth",
            "reconcile-tracking",
            "load-year",
            "reminders",
            "summary",
            "widget-snapshot",
        ])
    }

    @Test func coldForegroundLaunchReachesReadyAndReconcilesTracking() async throws {
        let model = try makeModel(status: .always, defaults: ephemeralDefaults())
        model.completeOnboarding() // not a first run
        let launcher = WhereLaunch.makeLauncher(model: model, reason: .userForeground)
        await launcher.run()
        #expect(launcher.phase.isReady)
        // .always authorization → the reconcile-tracking step resumed GPS,
        // proving the post-onboarding steps ran.
        #expect(model.isTracking)
    }

    @Test func firstRunForegroundLaunchPresentsOnboarding() async throws {
        let model = try makeModel(status: .notDetermined, defaults: ephemeralDefaults())
        #expect(!model.hasOnboarded)
        let launcher = WhereLaunch.makeLauncher(model: model, reason: .userForeground)
        let task = Task { @MainActor in await launcher.run() }

        try await waitUntil { launcher.phase.runningStepID == "onboarding" }
        #expect(launcher.phase.runningHandle?.presentation != nil)

        // Resolve the gate as OnboardingView would, letting the launch finish.
        launcher.phase.runningHandle?.complete()
        await task.value
        #expect(launcher.phase.isReady)
    }

    @Test func secondLaunchSkipsOnboarding() async throws {
        let defaults = ephemeralDefaults()
        let first = try makeModel(defaults: defaults)
        first.completeOnboarding()

        // A fresh model over the same defaults sees onboarding as done, so the
        // gate's condition is false and the launch never parks on onboarding.
        let model = try makeModel(defaults: defaults)
        let launcher = WhereLaunch.makeLauncher(model: model, reason: .userForeground)
        let task = Task { @MainActor in await launcher.run() }
        try await waitUntil { launcher.phase.isReady }
        await task.value
        #expect(launcher.phase.isReady)
    }

    @Test func backgroundLaunchSkipsOnboardingAndReachesReady() async throws {
        // Not onboarded — but a headless background launch must skip the
        // foreground-only onboarding step (waiting for a tap with no UI would
        // deadlock) and still run the rest.
        let model = try makeModel(status: .always, defaults: ephemeralDefaults())
        #expect(!model.hasOnboarded)
        let launcher = WhereLaunch.makeLauncher(model: model, reason: .background(.location))
        await launcher.run()
        #expect(launcher.phase.isReady)
        #expect(launcher.reason.isBackground)
        // The minimal background steps still ran (reconcile-tracking resumed GPS).
        #expect(model.isTracking)
    }

    @Test func freshInstallDoesNotPredictMigration() {
        // A model with no recorded version predicts no migration (a fresh
        // install is not a migration).
        let fresh = WhereModel(
            defaults: ephemeralDefaults(),
            schemaMarker: SchemaVersionMarker(
                defaults: ephemeralDefaults("fresh-marker"),
                currentVersion: Schema.Version(1, 0, 0),
            ),
        )
        #expect(!fresh.migrationExpected)
    }

    @Test func migrationPredictedPresentsMigrationUIDuringOpen() async throws {
        // A marker whose recorded version is behind the current schema predicts
        // a migration, which arms the open-store step's migration UI.
        let markerDefaults = ephemeralDefaults("marker")
        let key = "where.schemaVersion"
        markerDefaults.set("1.0.0", forKey: key)
        let marker = SchemaVersionMarker(
            defaults: markerDefaults,
            currentVersion: Schema.Version(2, 0, 0),
            key: key,
        )
        #expect(marker.migrationExpected)

        // A gated store opener parks the open-store step so its presentation is
        // deterministically observable (a real open is too fast to catch).
        // Onboarding is skipped and notifications disabled so the launch then
        // runs to completion without a tap or a permission prompt.
        let gate = OpenStoreGate()
        let model = WhereModel(
            defaults: ephemeralDefaults(),
            schemaMarker: marker,
            storeOpener: {
                await gate.waitUntilOpen()
                return try SwiftDataStore.inMemory()
            },
        )
        model.completeOnboarding()
        model.remindersEnabled = false
        model.summaryEnabled = false
        let launcher = WhereLaunch.makeLauncher(model: model, reason: .userForeground)
        let task = Task { @MainActor in await launcher.run() }

        try await waitUntil {
            launcher.phase.runningStepID == "open-store"
                && launcher.phase.runningHandle?.presentation != nil
        }

        await gate.open()
        await task.value
        #expect(launcher.phase.isReady)
    }
}

/// Test gate: holds the `open-store` step parked until the test releases it, so
/// the step's migration presentation is deterministically observable.
private actor OpenStoreGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func waitUntilOpen() async {
        if isOpen { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}
