import Foundation
import TestHostSupport
import Testing
@_spi(Testing) import WhereCore
import WhereUI

private struct WaitTimeout: Error {}

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

/// Covers the `WhereLaunch.reset` teardown the Settings "Erase all data &
/// reset" action runs: it cancels and drains the in-flight attempt, wipes the
/// store, stops tracking, drops the session, clears the preferences that gate
/// onboarding, then begins a fresh attempt back to the first-run state.
/// (Erase-before-preferences ordering is structural — one function, one
/// order; a thrown erase parks terminal `.failed` before preferences are
/// touched, which `reset`'s catch pins.)
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
            issueAlertScheduler: NoopDataIssueAlertScheduler(),
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
            issueAlertScheduler: NoopDataIssueAlertScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
        )
        return (WhereModel(services: services, preferences: preferences), source)
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

    @Test func eraseSessionClearsTheStoreAndStopsTracking() async throws {
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

        try await session.eraseSession()
        #expect(!session.isTracking)

        // The store really is empty, not just the in-memory report: a reload
        // from disk finds nothing.
        await report.refresh()
        #expect(report.trackedDayCount == 0)
    }

    @Test func endSessionDropsTheSessionAndAFreshAttemptRebuildsIt() async throws {
        let model = try makeModel(status: .always, preferences: makePreferences())
        model.completeOnboarding()
        let original = try #require(model.session)

        model.endSession()
        #expect(model.session == nil)

        // A fresh launch rebuilds a session from the retained (still-open)
        // services rather than reopening the store.
        let state = WhereLaunch.start(model: model)
        state.sceneBecameActive()
        try await waitUntil { state.phase.isReady }
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

        let state = WhereLaunch.start(model: model)
        state.sceneBecameActive()
        try await waitUntil { state.phase.isReady }

        // Reset relaunches into onboarding (hasOnboarded cleared); complete
        // it so the fresh attempt rebuilds a session and reaches .ready. The
        // strong reference to the original session is scoped so the weak
        // check below observes only the launch flow's own retention.
        do {
            let original = try #require(model.session)
            await WhereLaunch.reset(model: model, state: state, session: original)
        }
        try await waitUntil { state.phase.onboarding != nil }
        model.completeOnboarding()
        state.phase.onboarding?.handle.complete()
        try await waitUntil { state.phase.isReady }

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
        let state = WhereLaunch.start(model: model)
        state.sceneBecameActive()
        try await waitUntil { state.phase.isReady }

        let session = try #require(model.session)
        let report = YearReportModel(services: services, preferences: preferences)
        try await report.setManualDay(date: Date(), regions: [.california])
        await report.refresh()
        #expect(report.trackedDayCount == 1)

        // The reset drains the attempt, erases, and begins a fresh attempt —
        // which parks on onboarding again (hasOnboarded now cleared).
        await WhereLaunch.reset(model: model, state: state, session: session)
        try await waitUntil { state.phase.onboarding != nil }

        // Mid-relaunch: data erased, the session dropped + rebuilt, and the
        // onboarding gate reopened.
        #expect(!model.hasOnboarded)
        let rebuilt = try #require(model.session)
        #expect(rebuilt !== session)
        #expect(!rebuilt.isTracking)

        model.completeOnboarding()
        state.phase.onboarding?.handle.complete()
        try await waitUntil { state.phase.isReady }

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

        let state = WhereLaunch.start(model: model)
        state.sceneBecameActive()
        try await waitUntil { state.phase.isReady }
        let report = YearReportModel(services: services, preferences: preferences)
        try await report.setManualDay(date: Date(), regions: [.california])
        await report.refresh()
        #expect(report.trackedDayCount == 1)

        await WhereLaunch.reset(model: model, state: state, session: original)
        try await waitUntil { state.phase.onboarding != nil }

        // Mid-relaunch: the session was dropped and rebuilt fresh, and the
        // preferences were cleared (onboarding gate reopened; the reminder/summary
        // schedules default back on) — not the off state above.
        let rebuilt = try #require(model.session)
        #expect(rebuilt !== original)
        #expect(!model.hasOnboarded)
        #expect(preferences.remindersEnabled)
        #expect(preferences.summaryEnabled)

        model.completeOnboarding()
        state.phase.onboarding?.handle.complete()
        try await waitUntil { state.phase.isReady }
        // The store was wiped: a fresh report read against it is empty.
        await report.refresh()
        #expect(report.trackedDayCount == 0)
    }

    @Test func resetWhileParkedOnOnboardingDrainsTheOldAttempt() async throws {
        // A reset can land while the launch is parked on first-run onboarding.
        // The old attempt must drain (its handle cancelled, writing no phase)
        // and the fresh attempt must park on a NEW handle — resolving the
        // stale one is a no-op.
        let model = try makeModel(status: .notDetermined, preferences: makePreferences())
        #expect(!model.hasOnboarded)
        let state = WhereLaunch.start(model: model)
        state.sceneBecameActive()
        try await waitUntil { state.phase.onboarding != nil }
        let staleHandle = try #require(state.phase.onboarding?.handle)

        let session = try #require(model.session)
        await WhereLaunch.reset(model: model, state: state, session: session)
        try await waitUntil { state.phase.onboarding != nil }
        let freshHandle = try #require(state.phase.onboarding?.handle)
        #expect(freshHandle !== staleHandle)

        // The superseded attempt's handle is dead: resolving it changes
        // nothing (the launch stays parked on the fresh handle).
        staleHandle.complete()
        try await Task.sleep(for: .milliseconds(50))
        #expect(state.phase.onboarding?.handle === freshHandle)

        model.completeOnboarding()
        freshHandle.complete()
        try await waitUntil { state.phase.isReady }
    }
}
