import Foundation
import LifecycleKit
@_spi(Testing) import PeriscopeCore
import RegionKit
import TestHostSupport
import Testing
@_spi(Testing) import WhereCore
@_spi(Testing) @testable import WhereUI

private struct WaitTimeout: Error {}

/// Records destructive outbox cleanup without relying on timing. Launch tests read the count
/// from the services-ready hook to prove recovery completed before the later recording step.
private actor LaunchImportOutbox: LocationOutbox {
    private var clearCount = 0

    func load() async throws -> [LocationOutboxEntry] {
        []
    }

    func save(_: [LocationOutboxEntry]) async throws {}

    func clear() async throws {
        clearCount += 1
    }

    func numberOfClears() -> Int {
        clearCount
    }
}

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
        return WhereModel(services: services, preferences: preferences, logSystem: .isolated())
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
        return (
            WhereModel(services: services, preferences: preferences, logSystem: .isolated()),
            store,
            source,
        )
    }

    /// In-memory services, for a model that must assemble its scope lazily
    /// rather than having one injected up front.
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

    /// A logged-out model — no scope, nothing open — over a bootstrap that
    /// hands back in-memory services if and when the launch asks for them.
    /// The app's real shape at a first run.
    private func makeLoggedOutModel(
        status: LocationAuthorizationStatus = .always,
        preferences: WherePreferences,
        installationContextStore: InMemoryInstallationRecordingContextStore? = nil,
    ) throws -> (WhereModel, ScriptedBootstrap) {
        let installationContextStore = installationContextStore
            ?? makeInstallationRecordingContextStore()
        let bootstrap = try ScriptedBootstrap(services: makeServices(status: status))
        return (
            WhereModel(
                preferences: preferences,
                installationContextStore: installationContextStore,
                makeBootstrap: { _ in bootstrap },
                logSystem: .isolated(),
            ),
            bootstrap,
        )
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

    @Test func planNodesRunInStartParityOrder() throws {
        // The work steps mirror WhereSession.start()'s order; the only
        // insertions are the onboarding gate at the head and the
        // resolve-scope / start-session promotions behind it.
        let model = try makeModel(preferences: makePreferences())
        let ids = WhereLaunch.plan(for: model).nodeIDs
        #expect(ids == [
            .onboarding,
            .resolveScope,
            .startSession,
            .syncAuth,
            .reconcileTracking,
            .captureToday,
            .reminders,
            .summary,
            .issueAlerts,
            .widgetSnapshot,
        ])
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

    @Test func undeterminedLaunchDefersForegroundStepsUntilPromoted() async throws {
        // The app launches `.undetermined` (the UIScene lifecycle can't tell a
        // user launch from a headless wake yet). It must run only the
        // background-safe steps and build no view tree until a scene activates.
        let (model, store, source) = try makeModelAndStore(
            status: .always,
            preferences: makePreferences(),
        )
        model.completeOnboarding()
        source.setNextRequestedLocation(todayFix())

        let launcher = WhereLaunch.makeLauncher(model: model, reason: .undetermined)
        await launcher.run()
        // Reconcile-tracking (background-safe) resumed GPS, but the
        // foreground-only capture-today was skipped — nothing captured — and the
        // launch builds no view tree.
        #expect(launcher.phase.isReady)
        #expect(launcher.reason.buildsNoViewTree)
        #expect(model.session?.isTracking == true)
        #expect(try await store.allSamples().isEmpty)
        #expect(
            WhereLaunch.foregroundEnteredEvent(
                for: launcher,
                trigger: .sceneBecameActive,
            ) == .foregroundEntered(
                trigger: "scene-became-active",
                previousReason: "undetermined",
                previousPhase: "ready",
            ),
        )

        // A scene activates → promote. The re-drive skips the already-completed
        // background steps and runs the now-applicable foreground-only
        // capture-today, which logs today's fix.
        await WhereLaunch.enterForeground(launcher, trigger: .sceneBecameActive)
        #expect(launcher.phase.isReady)
        #expect(launcher.reason == .userForeground)
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

    @Test func firstRunForegroundLaunchParksOnTheOnboardingGateBeforeOpeningAnything() async throws {
        let (model, bootstrap) = try makeLoggedOutModel(
            status: .notDetermined,
            preferences: makePreferences(),
        )
        #expect(!model.hasOnboarded)
        let launcher = WhereLaunch.makeLauncher(model: model, reason: .userForeground)
        let task = Task { @MainActor in await launcher.run() }

        try await waitUntil { launcher.phase.isAwaitingGate(LaunchStepID.onboarding) }
        #expect(launcher.phase.gateHandle != nil)
        // The whole point of rooting the trunk at the gate: an install whose
        // user hasn't chosen yet has opened no store and built no session.
        #expect(bootstrap.makeServicesCount == 0)
        #expect(model.activeScope == nil)
        #expect(model.session == nil)

        // Resolve the gate as OnboardingView would, letting the launch finish.
        try model.confirmInitialRecordingChoice(isEnabled: true)
        model.completeOnboarding()
        launcher.phase.gateHandle?.complete()
        await task.value
        #expect(launcher.phase.isReady)
        #expect(bootstrap.makeServicesCount == 1)
        // .ready carries the session the trunk produced.
        #expect(launcher.phase.readyValue === model.session)
    }

    @Test func coldPreparedOnboardingImportWithoutReceiptReturnsToOnboarding() async throws {
        let installationStore = makeInstallationRecordingContextStore()
        let details = Self.onboardingRecoveryDetails()
        try installationStore.setBackupImportRecovery(.prepared(details))
        let services = try WhereServices(
            store: SwiftDataStore.inMemory(),
            locationSource: ScriptedLocationSource(),
            importRecoveryPersistence: installationStore,
        )
        let bootstrap = ScriptedBootstrap(services: services)
        let model = WhereModel(
            preferences: makePreferences(),
            installationContextStore: installationStore,
            makeBootstrap: { _ in bootstrap },
            logSystem: .isolated(),
        )

        let isNeeded = await OnboardingGate(model: model).isNeeded(())

        #expect(isNeeded)
        #expect(!model.hasOnboarded)
        #expect(model.activeScope == nil)
        #expect(installationStore.backupImportRecovery == nil)
    }

    @Test func coldCommittedOnboardingImportCompletesBeforeRestoreCanReappear() async throws {
        let installationStore = makeInstallationRecordingContextStore()
        let details = Self.onboardingRecoveryDetails()
        try installationStore.setBackupImportRecovery(.committed(
            details,
            cleanupCompleted: true,
            onboardingAcknowledged: false,
        ))
        let services = try WhereServices(
            store: SwiftDataStore.inMemory(),
            locationSource: ScriptedLocationSource(),
            importRecoveryPersistence: installationStore,
        )
        let bootstrap = ScriptedBootstrap(services: services)
        let model = WhereModel(
            preferences: makePreferences(),
            installationContextStore: installationStore,
            makeBootstrap: { _ in bootstrap },
            logSystem: .isolated(),
        )

        let isNeeded = await OnboardingGate(model: model).isNeeded(())

        #expect(!isNeeded)
        #expect(model.hasOnboarded)
        #expect(model.activeScope != nil)
        #expect(installationStore.backupImportRecovery == nil)
    }

    @Test func coldOnboardingRecoveryOpenFailureNeverFallsThroughToRestore() async throws {
        let installationStore = makeInstallationRecordingContextStore()
        try installationStore.setBackupImportRecovery(.committed(
            Self.onboardingRecoveryDetails(),
            cleanupCompleted: false,
            onboardingAcknowledged: false,
        ))
        let model = WhereModel(
            preferences: makePreferences(),
            installationContextStore: installationStore,
            makeBootstrap: { _ in FailingBootstrap() },
            logSystem: .isolated(),
        )

        let isNeeded = await OnboardingGate(model: model).isNeeded(())

        #expect(!isNeeded)
        #expect(!model.hasOnboarded)
        #expect(model.takeInterruptedOnboardingImportError() is FailingBootstrap.AssemblyFailure)
        #expect(installationStore.backupImportRecovery != nil)
    }

    private static func onboardingRecoveryDetails() -> BackupCoordinator.ImportRecoveryDetails {
        BackupCoordinator.ImportRecoveryDetails(
            transactionID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            strategy: .merge,
            summary: BackupCoordinator.ImportSummary(
                sampleCount: 3,
                evidenceCount: 2,
                manualDayCount: 1,
                dismissedIssueCount: 0,
                trackedRegionCount: 4,
                recordingDeviceCount: 0,
                recordingDeviceRemovalCount: 0,
            ),
        )
    }

    @Test func headlessFirstRunParksRatherThanOpeningTheStore() async throws {
        // A launch nobody can see must not open the user's store on their
        // behalf: the gate applies to every reason, so an `.undetermined`
        // drive parks exactly like a foreground one.
        let (model, bootstrap) = try makeLoggedOutModel(preferences: makePreferences())
        let launcher = WhereLaunch.makeLauncher(model: model, reason: .undetermined)
        let task = Task { @MainActor in await launcher.run() }

        try await waitUntil { launcher.phase.isAwaitingGate(LaunchStepID.onboarding) }
        #expect(bootstrap.makeServicesCount == 0)

        // Promotion supersedes the parked drive and parks again, now with a
        // scene to render the gate into.
        let promote = Task { @MainActor in await launcher.enterForeground() }
        try await waitUntil { launcher.reason == .userForeground }
        try await waitUntil { launcher.phase.isAwaitingGate(LaunchStepID.onboarding) }
        #expect(bootstrap.makeServicesCount == 0)

        try model.confirmInitialRecordingChoice(isEnabled: true)
        model.completeOnboarding()
        launcher.phase.gateHandle?.complete()
        await promote.value
        await task.value
        #expect(launcher.phase.isReady)
    }

    @Test func onboardedLaunchOpensTheStoreWithoutParking() async throws {
        let preferences = makePreferences()
        let (model, bootstrap) = try makeLoggedOutModel(preferences: preferences)
        model.completeOnboarding()

        let launcher = WhereLaunch.makeLauncher(model: model, reason: .userForeground)
        await launcher.run()

        #expect(launcher.phase.isReady)
        #expect(bootstrap.makeServicesCount == 1)
    }

    @Test func restoredInstallationParksForItsRecordingChoiceBeforeOpening() async throws {
        let preferences = makePreferences()
        preferences.hasOnboarded = true
        let installationContextStore = InMemoryInstallationRecordingContextStore(
            context: InstallationRecordingContext(
                currentDevice: CurrentRecordingDevice(
                    id: RecordingDeviceID(rawValue: UUID()),
                    systemName: "iPad",
                    kind: .tablet,
                ),
                registeredAt: Date(timeIntervalSinceReferenceDate: 0),
                recordingChoice: .unconfirmed,
                isRejoining: false,
            ),
        )
        let (model, bootstrap) = try makeLoggedOutModel(
            preferences: preferences,
            installationContextStore: installationContextStore,
        )
        let launcher = WhereLaunch.makeLauncher(model: model, reason: .userForeground)
        let task = Task { @MainActor in await launcher.run() }

        try await waitUntil { launcher.phase.isAwaitingGate(LaunchStepID.onboarding) }
        #expect(model.hasOnboarded)
        #expect(model.hasConfirmedRecordingChoice == false)
        #expect(bootstrap.makeServicesCount == 0)

        try model.confirmInitialRecordingChoice(isEnabled: false)
        launcher.phase.gateHandle?.complete()
        await task.value

        #expect(launcher.phase.isReady)
        #expect(bootstrap.makeServicesCount == 1)
    }

    @Test func aStoreThatCannotOpenFailsTheLaunch() async {
        // Lazy creation moved the store open behind the gate, but an
        // unopenable store must still park the runner in `.failed` rather than
        // reading as a launch that simply never finished.
        let preferences = makePreferences()
        preferences.hasOnboarded = true
        let model = WhereModel(
            preferences: preferences,
            installationContextStore: makeInstallationRecordingContextStore(),
            makeBootstrap: { _ in FailingBootstrap() },
            logSystem: .isolated(),
        )

        let launcher = WhereLaunch.makeLauncher(model: model, reason: .userForeground)
        await launcher.run()

        #expect(launcher.phase.failed(at: LaunchStepID.resolveScope))
        #expect(model.activeScope == nil)
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

    @Test func startSessionHandsTheSessionsServicesToTheOnServicesReadyHook() async throws {
        // A model with services attached but no session yet — the app's shape
        // when the resolve-scope step runs (the preview/test init pre-builds
        // the session; resolve-scope then reuses the injected scope).
        let store = try SwiftDataStore.inMemory()
        let services = WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(authorizationStatus: .always),
            reminderScheduler: NoopLoggingReminderScheduler(),
            summaryScheduler: NoopDailySummaryScheduler(),
            issueAlertScheduler: NoopDataIssueAlertScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
        )
        let preferences = makePreferences()
        let logSystem = Periscope.isolated()
        let model = WhereModel(
            preferences: preferences,
            installationContextStore: makeInstallationRecordingContextStore(),
            makeBootstrap: { _ in ScriptedBootstrap(services: services) },
            logSystem: logSystem,
        )
        model.activate(scope: .fake(
            services: services,
            preferences: preferences,
            logSystem: logSystem,
        ))
        model.completeOnboarding()

        var receivedJournals: [DayJournal] = []
        let launcher = WhereLaunch.makeLauncher(model: model, reason: .userForeground) {
            receivedJournals.append($0.journal)
        }
        await launcher.run()

        #expect(launcher.phase.isReady)
        // The hook fired exactly once, with the session's service layer (same
        // backing store) — the seam the app uses to install the App Intents
        // stack over the launch's one store open.
        #expect(receivedJournals.count == 1)
        #expect(receivedJournals.first === services.journal)
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
        let preferences = makePreferences()
        let logSystem = Periscope.isolated()
        let model = WhereModel(
            preferences: preferences,
            installationContextStore: makeInstallationRecordingContextStore(),
            makeBootstrap: { _ in ScriptedBootstrap(services: services) },
            logSystem: logSystem,
        )
        model.activate(scope: .fake(
            services: services,
            preferences: preferences,
            logSystem: logSystem,
        ))
        model.completeOnboarding()

        var hookFires = 0
        let launcher = WhereLaunch.makeLauncher(model: model, reason: .userForeground) { _ in
            hookFires += 1
        }
        await launcher.run()
        #expect(hookFires == 1)

        // The reset teardown drops the session and re-drives the launch; the
        // rebuilt session (over the retained, erased scope) must be handed to
        // the hook again so consumers ride the fresh session. The cleared
        // onboarding flag parks the relaunch on the onboarding gate — resolve
        // it as OnboardingView would.
        let session = try #require(model.session)
        let teardown = Task { @MainActor in
            await launcher.teardown(WhereLaunch.resetPlan(for: model), input: session)
        }
        try await waitUntil { launcher.phase.isAwaitingGate(LaunchStepID.onboarding) }
        // Still one: the session (and so the hook) comes *after* the gate now,
        // so a relaunch parked in onboarding has handed nothing to consumers.
        #expect(hookFires == 1)

        try model.confirmInitialRecordingChoice(isEnabled: true)
        model.completeOnboarding()
        launcher.phase.gateHandle?.complete()
        await teardown.value
        #expect(launcher.phase.isReady)
        #expect(hookFires == 2)
    }

    @Test func backgroundLaunchParksUntilTheInstallationIsConfirmed() async throws {
        // A headless launch must not open the store or infer consent for a new/restored
        // installation. It parks until a later foreground UI confirms the choice.
        let context = InstallationRecordingContext(
            currentDevice: CurrentRecordingDevice(
                id: RecordingDeviceID(rawValue: UUID()),
                systemName: "iPad",
                kind: .tablet,
            ),
            registeredAt: Date(timeIntervalSinceReferenceDate: 0),
            recordingChoice: .unconfirmed,
            isRejoining: false,
        )
        let (model, bootstrap) = try makeLoggedOutModel(
            status: .always,
            preferences: makePreferences(),
            installationContextStore: makeInstallationRecordingContextStore(context: context),
        )
        #expect(!model.hasOnboarded)
        let launcher = WhereLaunch.makeLauncher(model: model, reason: .background(.location))
        let run = Task { @MainActor in await launcher.run() }

        try await waitUntil { launcher.phase.isAwaitingGate(LaunchStepID.onboarding) }
        #expect(bootstrap.makeServicesCount == 0)
        #expect(model.session == nil)
        #expect(launcher.reason.buildsNoViewTree)

        try model.confirmInitialRecordingChoice(isEnabled: true)
        model.completeOnboarding()
        launcher.phase.gateHandle?.complete()
        await run.value

        #expect(launcher.phase.isReady)
        #expect(bootstrap.makeServicesCount == 1)
        #expect(model.session?.isTracking == true)
    }
}

/// Guards the one place the app opens a durable log store.
struct WhereBootstrapStorageTests {
    /// If this fails, a suite that logs in writes its records into the user's
    /// `Periscope.store` — and stalls on the test host's sandbox while doing
    /// it, rather than failing.
    @Test func durableLogStorageStaysInMemoryUnderTheTestRunner() {
        #expect(WhereBootstrap.logStorage == .inMemory)
    }
}
