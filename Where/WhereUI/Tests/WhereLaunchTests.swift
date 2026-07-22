import Foundation
@_spi(Testing) import PeriscopeCore
import RegionKit
import SwiftData
import TestHostSupport
import Testing
@_spi(Testing) import WhereCore
import WhereUI

private struct WaitTimeout: Error {}

private struct GateError: Error {}

/// Polls `predicate` on the main actor until it holds or the timeout elapses,
/// yielding to the launch task between checks.
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

/// Covers the `WhereLaunch.run` flow the app drives at startup: the headless
/// section above the scene-activation park, the foreground tail below it, the
/// onboarding park, and the `onServicesReady` composition hook.
@MainActor
struct WhereLaunchTests {
    private func makePreferences() -> WherePreferences {
        WherePreferences(store: InMemoryKeyValueStore())
    }

    /// A model with injected services (in-memory store, no-op schedulers)
    /// so the launch runs without touching real CoreLocation, the disk, or
    /// the notification center.
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

    @Test func headlessWakeIsServicedAboveTheParkWithoutBuildingTheTail() async throws {
        // A headless launch (no scene ever activates) must service the wake —
        // store open, session, authorization, tracking — and then park before
        // the foreground tail: no onboarding, no one-shot fix, no .ready.
        let (model, store, source) = try makeModelAndStore(
            status: .always,
            preferences: makePreferences(),
        )
        source.setNextRequestedLocation(todayFix())
        // Deliberately NOT onboarded: the park sits above the onboarding
        // check, so a headless wake never deadlocks on a first-run gate.
        let state = WhereLaunch.start(model: model)

        try await waitUntil { model.session?.isTracking == true }
        // Parked: still .launching, nothing captured, no scene ever active.
        try await Task.sleep(for: .milliseconds(50))
        #expect(state.phase.isLaunching)
        #expect(!state.sceneHasBeenActive)
        #expect(try await store.allSamples().isEmpty)
    }

    @Test func sceneActivationResumesTheForegroundTailToReady() async throws {
        let (model, store, source) = try makeModelAndStore(
            status: .always,
            preferences: makePreferences(),
        )
        model.completeOnboarding()
        source.setNextRequestedLocation(todayFix())
        let state = WhereLaunch.start(model: model)

        // Let the headless half finish, then promote — the parked task
        // resumes; nothing re-runs because nothing is driven twice.
        try await waitUntil { model.session?.isTracking == true }
        state.sceneBecameActive()

        try await waitUntil { state.phase.isReady }
        // .ready carries the session the launch produced.
        #expect(state.phase.readyValue === model.session)
        // The foreground tail spent the one-shot fix (non-blocking; wait for
        // the persist to land).
        try await waitUntilAsync { await (try? store.allSamples().count) == 1 }
    }

    @Test func alreadyActiveSceneRunsStraightThroughToReady() async throws {
        let model = try makeModel(status: .always, preferences: makePreferences())
        model.completeOnboarding()
        let state = WhereLaunch.start(model: model)
        state.sceneBecameActive()

        try await waitUntil { state.phase.isReady }
        #expect(model.session?.isTracking == true)
    }

    @Test func firstRunParksOnOnboardingAfterActivation() async throws {
        let model = try makeModel(status: .notDetermined, preferences: makePreferences())
        #expect(!model.hasOnboarded)
        let state = WhereLaunch.start(model: model)
        state.sceneBecameActive()

        try await waitUntil { state.phase.onboarding != nil }
        let onboarding = try #require(state.phase.onboarding)
        // The parked phase hands the view the session it commits regions
        // with — not left to find one in the environment.
        #expect(onboarding.session === model.session)

        // Resolve as OnboardingView would, letting the launch finish.
        model.completeOnboarding()
        onboarding.handle.complete()
        try await waitUntil { state.phase.isReady }
        #expect(state.phase.readyValue === model.session)
    }

    @Test func secondLaunchSkipsOnboarding() async throws {
        let preferences = makePreferences()
        let first = try makeModel(preferences: preferences)
        first.completeOnboarding()

        // A fresh model over the same preferences sees onboarding as done, so
        // the launch's `if` takes the other branch and never parks.
        let model = try makeModel(preferences: preferences)
        let state = WhereLaunch.start(model: model)
        state.sceneBecameActive()
        try await waitUntil { state.phase.isReady }
    }

    @Test func onboardingFailureIsTerminal() async throws {
        // Failure is terminal by design: the phase parks in .failed and there
        // is no retry API — the recovery is relaunching the app.
        let model = try makeModel(status: .notDetermined, preferences: makePreferences())
        let state = WhereLaunch.start(model: model)
        state.sceneBecameActive()

        try await waitUntil { state.phase.onboarding != nil }
        state.phase.onboarding?.handle.fail(GateError())
        try await waitUntil { state.phase.failure != nil }
        #expect(state.phase.failure is GateError)
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

    @Test func startHandsTheSessionsServicesToTheOnServicesReadyHook() async throws {
        // A model with services attached but no session yet — the app's shape
        // when the launch runs.
        let store = try SwiftDataStore.inMemory()
        let services = WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(authorizationStatus: .always),
            reminderScheduler: NoopLoggingReminderScheduler(),
            summaryScheduler: NoopDailySummaryScheduler(),
            issueAlertScheduler: NoopDataIssueAlertScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
        )
        let model = WhereModel(preferences: makePreferences())
        model.attach(services: services)
        model.completeOnboarding()

        var receivedContainers: [ModelContainer?] = []
        let state = WhereLaunch.start(model: model) {
            receivedContainers.append($0.modelContainer)
        }
        state.sceneBecameActive()
        try await waitUntil { state.phase.isReady }

        // The hook fired exactly once, with the session's service layer (same
        // backing store) — the seam the app uses to install the App Intents
        // stack over the launch's one store open. It fires above the park, so
        // a headless wake's intents resolve too.
        #expect(receivedContainers.count == 1)
        let receivedContainer = receivedContainers.first ?? nil
        #expect(receivedContainer === store.inspectorContainer)
    }

    @Test func resetRelaunchHandsTheFreshSessionsServicesToTheHookAgain() async throws {
        let store = try SwiftDataStore.inMemory()
        let services = WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(authorizationStatus: .always),
            reminderScheduler: NoopLoggingReminderScheduler(),
            summaryScheduler: NoopDailySummaryScheduler(),
            issueAlertScheduler: NoopDataIssueAlertScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
        )
        let model = WhereModel(preferences: makePreferences())
        model.attach(services: services)
        model.completeOnboarding()

        var hookFires = 0
        let state = WhereLaunch.start(model: model) { _ in
            hookFires += 1
        }
        state.sceneBecameActive()
        try await waitUntil { state.phase.isReady }
        #expect(hookFires == 1)

        // The reset drops the session and begins a fresh attempt; the rebuilt
        // session (over the retained, erased services) must be handed to the
        // hook again so consumers ride the fresh session. The cleared
        // onboarding flag parks the relaunch on onboarding — resolve it as
        // OnboardingView would.
        let session = try #require(model.session)
        await WhereLaunch.reset(model: model, state: state, session: session)
        try await waitUntil { state.phase.onboarding != nil }
        #expect(hookFires == 2)
        model.completeOnboarding()
        state.phase.onboarding?.handle.complete()
        try await waitUntil { state.phase.isReady }
    }
}
