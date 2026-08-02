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

/// Covers the `WhereLaunch.resetPlan(for:)` teardown the Settings "Erase all
/// data & reset" action runs through `LifecycleRunner.teardown`: it wipes the
/// store, stops tracking, drops the session, clears the preferences that gate
/// onboarding, then re-drives the launch back to its first-run state.
@MainActor
struct WhereResetTests {
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
        try WhereModel(
            services: makeServices(status: status),
            preferences: preferences,
            logSystem: .isolated(),
        )
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
        return (
            WhereModel(services: services, preferences: preferences, logSystem: .isolated()),
            source,
        )
    }

    @Test func resetPlanErasesThenClearsPreferences() throws {
        let model = try makeModel(preferences: makePreferences())
        let ids = WhereLaunch.resetPlan(for: model).nodeIDs
        #expect(ids == [.eraseData, .resetPreferences])
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
        #expect(model.hasConfirmedRecordingChoice)

        model.resetPreferences()

        // Removing the keys lets the default-valued getters report first-install
        // state again: onboarding returns and reminders/summary default back on.
        #expect(model.hasOnboarded == false)
        #expect(model.hasConfirmedRecordingChoice == false)
        #expect(preferences.remindersEnabled)
        #expect(preferences.summaryEnabled)
    }

    @Test func eraseAllDataClearsTheStoreAndStopsTracking() async throws {
        let preferences = makePreferences()
        let services = try makeServices(status: .always)
        let model = WhereModel(services: services, preferences: preferences, logSystem: .isolated())
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

    @Test func endSessionReleasesTheScopeAndRelaunchBuildsAFreshOne() async throws {
        let model = try makeModel(status: .always, preferences: makePreferences())
        model.completeOnboarding()
        let original = try #require(model.session)
        let scope = try #require(model.activeScope)

        await model.endSession()
        #expect(model.session == nil)
        // Logging out releases the scope rather than parking it: the next
        // login builds its own, and nothing keeps the old store alive.
        #expect(model.activeScope == nil)

        let launcher = WhereLaunch.makeLauncher(model: model, reason: .userForeground)
        await launcher.run()
        #expect(launcher.phase.isReady)
        let rebuilt = try #require(model.session)
        #expect(rebuilt !== original)
        #expect(model.activeScope !== scope)
    }

    @Test func loggingOutReleasesTheScopeBeforeTheNextLoginOpensOne() async throws {
        // The store is opened once per *login*, not once per process: the reset
        // teardown releases the scope, and onboarding builds a new one. The
        // onboarding gate sits between the two, so the old container is gone
        // before the new one opens.
        let preferences = makePreferences()
        let bootstrap = try ScriptedBootstrap(services: makeServices())
        let model = WhereModel(
            preferences: preferences,
            makeBootstrap: { bootstrap },
            logSystem: .isolated(),
        )
        model.completeOnboarding()

        let launcher = WhereLaunch.makeLauncher(model: model, reason: .userForeground)
        await launcher.run()
        #expect(bootstrap.makeServicesCount == 1)
        let scope = try #require(model.activeScope)

        let session = try #require(model.session)
        let task = Task { @MainActor in
            await launcher.teardown(WhereLaunch.resetPlan(for: model), input: session)
        }
        try await waitUntil { launcher.phase.isAwaitingGate(LaunchStepID.onboarding) }
        // Parked with nothing open: the scope is released and the relaunch is
        // waiting on the user before it builds another.
        #expect(model.activeScope == nil)
        #expect(bootstrap.makeServicesCount == 1)

        launcher.phase.gateHandle?.complete()
        await task.value

        #expect(launcher.phase.isReady)
        #expect(bootstrap.makeServicesCount == 2)
        #expect(model.activeScope !== scope)
    }

    @Test func loggingOutTellsTheCompositionRoot() async throws {
        // The App Intents stack holds services derived from the scope, and
        // nothing else would release them before the next login opens another
        // container over the same file.
        let model = try makeModel(preferences: makePreferences())
        var logOuts = 0
        model.onLoggedOut = { logOuts += 1 }

        await model.endSession()
        #expect(logOuts == 1)
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
                await launcher.teardown(WhereLaunch.resetPlan(for: model), input: original)
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
        let model = WhereModel(services: services, preferences: preferences, logSystem: .isolated())
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
            await launcher.teardown(WhereLaunch.resetPlan(for: model), input: session)
        }
        try await waitUntil { launcher.phase.isAwaitingGate(LaunchStepID.onboarding) }

        // Teardown ran before the relaunch reached onboarding: data erased, the
        // preferences cleared, and the app logged out — parked at the gate with
        // no session, since the relaunch rebuilds one only once the user has
        // chosen a world again.
        #expect(model.hasOnboarded == false)
        #expect(model.hasConfirmedRecordingChoice == false)
        #expect(model.session == nil)
        #expect(launcher.phase.gateHandle != nil)
        // The erase quiesced GPS before wiping, so the torn-down session is no
        // longer tracking and can't write into the store as it's cleared.
        #expect(!session.isTracking)

        launcher.phase.gateHandle?.complete()
        await task.value

        #expect(launcher.phase.isReady)
        // Resolving the gate rebuilt a fresh session over the erased scope.
        let rebuilt = try #require(model.session)
        #expect(rebuilt !== session)
        // The store was wiped: a fresh report read against it finds nothing.
        await report.refresh()
        #expect(report.trackedDayCount == 0)
    }

    @Test func resetDropsSessionClearsPreferencesAndReturnsToOnboarding() async throws {
        // The end-to-end reset cycle: a user who has onboarded, turned the
        // reminders/summary off, and logged a day runs "Erase all data & reset".
        let preferences = makePreferences()
        let services = try makeServices(status: .always)
        let model = WhereModel(services: services, preferences: preferences, logSystem: .isolated())
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
            await launcher.teardown(WhereLaunch.resetPlan(for: model), input: original)
        }
        try await waitUntil { launcher.phase.isAwaitingGate(LaunchStepID.onboarding) }

        // Mid-relaunch: the session was dropped (the relaunch is parked before
        // it rebuilds one) and the preferences were cleared — onboarding gate
        // reopened, reminder/summary schedules defaulted back on rather than
        // the off state above.
        #expect(model.session == nil)
        #expect(model.hasOnboarded == false)
        #expect(model.hasConfirmedRecordingChoice == false)
        #expect(preferences.remindersEnabled)
        #expect(preferences.summaryEnabled)

        launcher.phase.gateHandle?.complete()
        await task.value
        #expect(launcher.phase.isReady)
        let rebuilt = try #require(model.session)
        #expect(rebuilt !== original)
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

        let failing = LaunchPlan(FailingEraseStep())
            .then(ResetPreferencesProbeStep(model: model))
        let launcher = WhereLaunch.makeLauncher(model: model, reason: .userForeground)
        await launcher.run()
        #expect(launcher.phase.isReady)

        let session = try #require(model.session)
        await launcher.teardown(failing, input: session)
        #expect(launcher.phase.failed(at: LaunchStepID.eraseData))
        #expect(model.hasOnboarded) // reset-preferences never ran
        #expect(model.hasConfirmedRecordingChoice)
    }
}

/// An erase stand-in that always throws, so the teardown-failure path can be
/// driven without corrupting a real store.
private struct FailingEraseStep: LifecycleStep {
    let id = LaunchStepID.eraseData

    func run(_: WhereSession, _: LifecycleStepContext) async throws {
        throw CocoaError(.fileWriteUnknown)
    }
}

/// The real reset-preferences behavior behind the failing erase, proving it
/// never runs when the erase throws.
private struct ResetPreferencesProbeStep: LifecycleStep {
    let model: WhereModel

    let id = LaunchStepID.resetPreferences

    func run(_: Void, _: LifecycleStepContext) async throws {
        model.resetPreferences()
    }
}
