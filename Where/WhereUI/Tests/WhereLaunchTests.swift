import Foundation
import LifecycleKit
@_spi(Testing) import PeriscopeCore
import RegionKit
import TestHostSupport
import Testing
@_spi(Testing) import WhereCore
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

/// Async-predicate variant of `waitUntil`, for polling actor-isolated state
/// (e.g. the store's sample count) that must be `await`ed.
@MainActor
private func waitUntilAsync(
    timeout: Duration = .seconds(5),
    _ predicate: () async -> Bool,
) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while await !predicate() {
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
            issueAlertScheduler: NoopDataIssueAlertScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
        )
        return WhereModel(services: services, preferences: preferences)
    }

    /// Like `makeModel`, but returns the backing store and location source so a
    /// test can script a one-shot fix and assert what the launch persisted.
    private func makeModelAndStore(
        status: LocationAuthorizationStatus = .always,
        preferences: WherePreferences,
    ) throws -> (WhereModel, SwiftDataStore, ScriptedLocationSource) {
        let store = try SwiftDataStore.inMemory()
        let source = ScriptedLocationSource(authorizationStatus: status)
        let services = WhereServices(
            store: store,
            locationSource: source,
            reminderScheduler: NoopLoggingReminderScheduler(),
            summaryScheduler: NoopDailySummaryScheduler(),
            issueAlertScheduler: NoopDataIssueAlertScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
        )
        return (WhereModel(services: services, preferences: preferences), store, source)
    }

    /// A one-shot fix stamped "now" so it lands on today's calendar day.
    private func todayFix() -> LocationSample {
        LocationSample(
            timestamp: Date(),
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 5,
            source: .gpsSignificantChange,
        )
    }

    @Test func sequenceStepsRunInStartParityOrder() throws {
        // The work steps mirror WhereSession.start()'s order; the only insertion
        // is the onboarding gate.
        let model = try makeModel(preferences: makePreferences())
        let ids = WhereLaunch.sequence(for: model).steps.map(\.id)
        #expect(ids == [
            LaunchStepID.openStore,
            .onboarding,
            .syncAuth,
            .reconcileTracking,
            .captureToday,
            .reminders,
            .summary,
            .issueAlerts,
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

    @Test func coldForegroundLaunchCapturesTodayWhenEmpty() async throws {
        let (model, store, source) = try makeModelAndStore(
            status: .always,
            preferences: makePreferences(),
        )
        model.completeOnboarding()
        source.setNextRequestedLocation(todayFix())

        let launcher = WhereLaunch.makeLauncher(model: model, reason: .userForeground)
        await launcher.run()
        #expect(launcher.phase.isReady)

        // The capture-today step logged today's fix (non-blocking, so wait for
        // the persist to land).
        try await waitUntilAsync { await (try? store.allSamples().count) == 1 }
    }

    @Test func backgroundLaunchSkipsCaptureToday() async throws {
        // The capture-today step is foreground-only: a headless background
        // relaunch is itself the passive location event, so it must not fire a
        // fresh foreground fix even though authorization/intent would allow one.
        let (model, store, source) = try makeModelAndStore(
            status: .always,
            preferences: makePreferences(),
        )
        model.completeOnboarding()
        source.setNextRequestedLocation(todayFix())

        let launcher = WhereLaunch.makeLauncher(model: model, reason: .background(.location))
        await launcher.run()
        #expect(launcher.phase.isReady)

        // Skipped → nothing captured. (reconcile-tracking started monitoring but
        // the scripted source emits no passive samples on its own.)
        #expect(try await store.allSamples().isEmpty)
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

    @Test func attachingLogStoreExposesItOnTheModel() async throws {
        // The launch bootstrap opens the process-global store off the critical
        // path and hands it to the model so the developer surface can browse it.
        // A fresh model has none until then.
        let model = try makeModel(preferences: makePreferences())
        #expect(model.logStore == nil)
        let store = try await PeriscopeStore.inMemory(session: .current())
        model.attach(logStore: store)
        #expect(model.logStore === store)
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
