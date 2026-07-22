import Foundation
import LifecycleKit
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

/// Covers the `WhereLaunch.reset(for:)` teardown the Settings "Erase all
/// data & reset" action runs through `LifecycleRunner.teardown`: it wipes the
/// store, stops tracking, drops the session, clears the preferences that gate
/// onboarding, then re-runs the launch back to its first-run state. (The
/// erase-before-preferences ordering is pinned behaviorally by
/// `resetFailureParksLauncherAndKeepsPreferences` — a failed erase must leave
/// the onboarding flag untouched.)
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

        try await session.eraseSession()
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
        weak let weakOriginal = model.session

        let launcher = WhereLaunch.makeLauncher(model: model, reason: .userForeground)
        await launcher.run()
        #expect(launcher.phase.isReady)

        // Reset re-drives into onboarding (hasOnboarded cleared); complete it
        // so the relaunch rebuilds a fresh session and reaches .ready. The
        // strong reference to the original session is scoped to the task's
        // closure (released when the teardown finishes), so the weak check
        // below observes only the runner's own retention.
        let task: Task<Void, Never>
        do {
            let original = try #require(model.session)
            task = Task { @MainActor in
                await launcher.teardown(input: original, WhereLaunch.reset(for: model))
            }
        }
        try await waitUntil { launcher.phase.isAwaitingGate(LaunchStepID.onboarding) }
        launcher.phase.gateHandle?.complete()
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

        // reset re-drives the launch, which parks on the onboarding gate again
        // (now that hasOnboarded is cleared), so the teardown doesn't return
        // until onboarding is resolved — drive it from a task and wait for the
        // parked gate.
        let task = Task { @MainActor in
            await launcher.teardown(input: session, WhereLaunch.reset(for: model))
        }
        try await waitUntil { launcher.phase.isAwaitingGate(LaunchStepID.onboarding) }

        // Teardown ran before the relaunch reached onboarding: data erased, the
        // session dropped + rebuilt, and the onboarding gate reopened.
        #expect(!model.hasOnboarded)
        let rebuilt = try #require(model.session)
        #expect(rebuilt !== session)
        #expect(!rebuilt.isTracking)
        #expect(launcher.phase.gateHandle != nil)

        launcher.phase.gateHandle?.complete()
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
            await launcher.teardown(input: original, WhereLaunch.reset(for: model))
        }
        try await waitUntil { launcher.phase.isAwaitingGate(LaunchStepID.onboarding) }

        // Mid-relaunch: the session was dropped and rebuilt fresh, and the
        // preferences were cleared (onboarding gate reopened; the reminder/summary
        // schedules default back on) — not the off state above.
        let rebuilt = try #require(model.session)
        #expect(rebuilt !== original)
        #expect(!model.hasOnboarded)
        #expect(preferences.remindersEnabled)
        #expect(preferences.summaryEnabled)

        launcher.phase.gateHandle?.complete()
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

        let launcher = WhereLaunch.makeLauncher(model: model, reason: .userForeground)
        await launcher.run()
        #expect(launcher.phase.isReady)

        // An erase stand-in that always throws, so the teardown-failure path
        // can be driven without corrupting a real store; the real
        // reset-preferences behavior follows it, proving it never runs.
        let session = try #require(model.session)
        await launcher.teardown(input: session) { _, context in
            try await context.step(LaunchStepID.eraseData) {
                throw CocoaError(.fileWriteUnknown)
            }
            try await context.step(LaunchStepID.resetPreferences) {
                model.resetPreferences()
            }
        }
        #expect(launcher.phase.failed(at: LaunchStepID.eraseData))
        #expect(model.hasOnboarded) // reset-preferences never ran
    }
}
