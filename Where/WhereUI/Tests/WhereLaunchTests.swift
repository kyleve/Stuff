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

/// Covers the `WhereLaunch` sequence the app drives at startup: the step order
/// (parity with `WhereSession.start()`), the onboarding gate, and the headless
/// background path.
@MainActor
struct WhereLaunchTests {
    private func makePreferences() -> WherePreferences {
        WherePreferences(store: InMemoryKeyValueStore())
    }

    /// A model with injected services (in-memory store, no-op schedulers)
    /// so the launch sequence runs without touching real CoreLocation, the
    /// disk, or the notification center.
    private func makeModel(
        status: LocationAuthorizationStatus = .always,
        preferences: WherePreferences,
    ) throws -> WhereModel {
        let services = try WhereServices(
            store: SwiftDataStore.inMemory(),
            locationSource: ScriptedLocationSource(authorizationStatus: status),
            reminderScheduler: NoopLoggingReminderScheduler(),
            summaryScheduler: NoopDailySummaryScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
        )
        return WhereModel(services: services, preferences: preferences)
    }

    @Test func sequenceStepsRunInStartParityOrder() throws {
        // The work steps mirror WhereSession.start()'s order; the only insertions
        // are open-store's migration presentation and the onboarding gate.
        let model = try makeModel(preferences: makePreferences())
        let ids = WhereLaunch.sequence(for: model).steps.map(\.id)
        #expect(ids == [
            LaunchStepID.openStore,
            .onboarding,
            .syncAuth,
            .reconcileTracking,
            .loadYear,
            .reminders,
            .summary,
            .widgetSnapshot,
        ].map { AnyHashable($0) })
    }

    @Test func coldForegroundLaunchReachesReadyAndReconcilesTracking() async throws {
        let model = try makeModel(status: .always, preferences: makePreferences())
        model.completeOnboarding() // not a first run
        let launcher = WhereLaunch.makeLauncher(model: model, reason: .userForeground)
        await launcher.run()
        #expect(launcher.phase.isReady)
        // .always authorization → the reconcile-tracking step resumed GPS,
        // proving the post-onboarding steps ran.
        #expect(model.session?.isTracking == true)
    }

    @Test func firstRunForegroundLaunchPresentsOnboarding() async throws {
        let model = try makeModel(status: .notDetermined, preferences: makePreferences())
        #expect(!model.hasOnboarded)
        let launcher = WhereLaunch.makeLauncher(model: model, reason: .userForeground)
        let task = Task { @MainActor in await launcher.run() }

        try await waitUntil { launcher.phase.isRunning(LaunchStepID.onboarding) }
        #expect(launcher.phase.runningBridge?.presentation != nil)

        // Resolve the gate as OnboardingView would, letting the launch finish.
        launcher.phase.runningBridge?.complete()
        await task.value
        #expect(launcher.phase.isReady)
    }

    @Test func secondLaunchSkipsOnboarding() async throws {
        let preferences = makePreferences()
        let first = try makeModel(preferences: preferences)
        first.completeOnboarding()

        // A fresh model over the same preferences sees onboarding as done, so the
        // gate's condition is false and the launch never parks on onboarding.
        let model = try makeModel(preferences: preferences)
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
        let model = try makeModel(status: .always, preferences: makePreferences())
        #expect(!model.hasOnboarded)
        let launcher = WhereLaunch.makeLauncher(model: model, reason: .background(.location))
        await launcher.run()
        #expect(launcher.phase.isReady)
        #expect(launcher.reason.isBackground)
        // The minimal background steps still ran (reconcile-tracking resumed GPS).
        #expect(model.session?.isTracking == true)
    }
}
