import Foundation
import LifecycleKit
@_spi(Testing) import PeriscopeCore
import RegionKit
import Testing
@_spi(Testing) import WhereCore
import WhereUI

private struct WaitTimeout: Error {}

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

/// Covers demo mode's contract: that entering it logs the app in to a
/// throwaway world, that the user's real preferences and store are untouched
/// while it runs (and never created at all if they were never opened), and
/// that leaving returns the app to where a logged-out user belongs.
@MainActor
struct DemoModeTests {
    private func makePreferences() -> WherePreferences {
        WherePreferences(store: InMemoryKeyValueStore())
    }

    /// A logged-out model over an isolated logging system, with in-memory
    /// services waiting behind a scripted bootstrap.
    private func makeModel(
        preferences: WherePreferences,
        logSystem: Periscope = .isolated(),
    ) throws -> (WhereModel, ScriptedBootstrap) {
        let bootstrap = try ScriptedBootstrap(services: makeServices())
        return (
            WhereModel(preferences: preferences, bootstrap: bootstrap, logSystem: logSystem),
            bootstrap,
        )
    }

    private func makeServices() throws -> WhereServices {
        try WhereServices(
            store: SwiftDataStore.inMemory(),
            locationSource: ScriptedLocationSource(),
            reminderScheduler: NoopLoggingReminderScheduler(),
            summaryScheduler: NoopDailySummaryScheduler(),
            issueAlertScheduler: NoopDataIssueAlertScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
        )
    }

    @Test func demoScopeIsSeededAndSelfContained() async throws {
        let (model, _) = try makeModel(preferences: makePreferences())
        let scope = try await model.makeDemoScope()

        // A year to look at, attributed to the two regions the demo tracks.
        let year = Calendar(identifier: .gregorian).component(.year, from: Date())
        let report = try await scope.services.reports.yearReport(for: year)
        #expect(!report.days.isEmpty)
        let regions = report.days.flatMap(\.regions)
        #expect(Set(regions) == [.newYork, .california])

        // Onboarded and tracking, so the demo opens on the logged-in app.
        #expect(scope.preferences.hasOnboarded)
        #expect(scope.preferences.wantsTracking)

        // Its log store is in memory, like everything else it owns.
        #expect(scope.logStore != nil)
        await scope.detachLogSink()
    }

    @Test func demoPreferencesNeverReachTheRealOnes() async throws {
        let realPreferences = makePreferences()
        let (model, _) = try makeModel(preferences: realPreferences)
        try await model.activateDemo(model.makeDemoScope())

        // The demo's own preferences say onboarded; the user's still say they
        // aren't, which is what makes quitting mid-demo return to onboarding.
        #expect(model.isInDemoMode)
        #expect(!realPreferences.hasOnboarded)
        #expect(!model.hasOnboarded)

        await model.deactivateDemo()
        #expect(!model.isInDemoMode)
        #expect(!realPreferences.hasOnboarded)
    }

    @Test func demoingFromAFreshInstallOpensNoRealStore() async throws {
        // The strongest isolation claim: someone who only ever tries the demo
        // leaves no store behind, because none is ever assembled.
        let preferences = makePreferences()
        let (model, bootstrap) = try makeModel(preferences: preferences)

        let launcher = WhereLaunch.makeLauncher(model: model, reason: .userForeground)
        let task = Task { @MainActor in await launcher.run() }
        try await waitUntil { launcher.phase.isAwaitingGate(LaunchStepID.onboarding) }

        // Enter demo mode the way the intro button does: activate the scope,
        // then resolve the gate.
        try await model.activateDemo(model.makeDemoScope())
        launcher.phase.gateHandle?.complete()
        await task.value

        #expect(launcher.phase.isReady)
        #expect(model.isInDemoMode)
        #expect(bootstrap.makeServicesCount == 0)

        await model.deactivateDemo()
    }

    @Test func demoSessionRunsOnTheDemoStore() async throws {
        let preferences = makePreferences()
        let (model, _) = try makeModel(preferences: preferences)

        let launcher = WhereLaunch.makeLauncher(model: model, reason: .userForeground)
        let task = Task { @MainActor in await launcher.run() }
        try await waitUntil { launcher.phase.isAwaitingGate(LaunchStepID.onboarding) }
        let scope = try await model.makeDemoScope()
        await model.activateDemo(scope)
        launcher.phase.gateHandle?.complete()
        await task.value

        // The launch built a session, and it was built over the demo scope —
        // so the logged-in UI reads the seeded demo year rather than the
        // user's (here, nonexistent) data.
        #expect(model.session != nil)
        #expect(model.activeScope === scope)
        let year = Calendar(identifier: .gregorian).component(.year, from: Date())
        let report = try await scope.services.reports.yearReport(for: year)
        #expect(!report.days.isEmpty)

        await model.deactivateDemo()
    }

    @Test func demoingAfterAResetLeavesTheRealScopeIntact() async throws {
        // The only way an existing user reaches the demo button is by resetting
        // first, which leaves their (now erased) scope dormant. Trying the demo
        // and leaving it again must hand that same scope back — never open a
        // second container over the same store file.
        let preferences = makePreferences()
        let (model, bootstrap) = try makeModel(preferences: preferences)
        model.completeOnboarding()

        let launcher = WhereLaunch.makeLauncher(model: model, reason: .userForeground)
        await launcher.run()
        let realScope = try #require(model.activeScope)
        #expect(bootstrap.makeServicesCount == 1)

        // Reset: parks on the onboarding gate with the real scope dormant.
        let realSession = try #require(model.session)
        let reset = Task { @MainActor in
            await launcher.teardown(WhereLaunch.resetPlan(for: model), input: realSession)
        }
        try await waitUntil { launcher.phase.isAwaitingGate(LaunchStepID.onboarding) }

        // Try the demo from there.
        let demoScope = try await model.makeDemoScope()
        await model.activateDemo(demoScope)
        launcher.phase.gateHandle?.complete()
        await reset.value
        #expect(launcher.phase.isReady)
        #expect(model.isInDemoMode)
        #expect(model.activeScope === demoScope)

        // Leave it: back to the gate, out of demo mode, real scope untouched.
        let demoSession = try #require(model.session)
        let exit = Task { @MainActor in
            await launcher.teardown(WhereLaunch.exitDemoPlan(for: model), input: demoSession)
        }
        try await waitUntil { launcher.phase.isAwaitingGate(LaunchStepID.onboarding) }
        #expect(!model.isInDemoMode)

        // Logging back in returns the dormant scope rather than assembling one.
        launcher.phase.gateHandle?.complete()
        await exit.value
        #expect(launcher.phase.isReady)
        #expect(model.activeScope === realScope)
        #expect(bootstrap.makeServicesCount == 1)
    }

    @Test func exitingDemoFromAFreshInstallReturnsToOnboarding() async throws {
        let preferences = makePreferences()
        let (model, bootstrap) = try makeModel(preferences: preferences)

        let launcher = WhereLaunch.makeLauncher(model: model, reason: .userForeground)
        let launch = Task { @MainActor in await launcher.run() }
        try await waitUntil { launcher.phase.isAwaitingGate(LaunchStepID.onboarding) }
        try await model.activateDemo(model.makeDemoScope())
        launcher.phase.gateHandle?.complete()
        await launch.value

        let session = try #require(model.session)
        let teardown = Task { @MainActor in
            await launcher.teardown(WhereLaunch.exitDemoPlan(for: model), input: session)
        }
        // Never onboarded for real, so leaving the demo parks on the intro
        // again rather than dropping them into an empty app.
        try await waitUntil { launcher.phase.isAwaitingGate(LaunchStepID.onboarding) }
        #expect(!model.isInDemoMode)
        #expect(model.session == nil)
        #expect(bootstrap.makeServicesCount == 0)

        launcher.phase.gateHandle?.complete()
        await teardown.value
    }

    @Test func exitDemoPlanIsASingleStep() throws {
        let (model, _) = try makeModel(preferences: makePreferences())
        #expect(WhereLaunch.exitDemoPlan(for: model).nodeIDs == [.exitDemo])
    }

    // MARK: - Log routing

    /// Records emitted while a world is active must reach that world's log
    /// store and no other. Asserted by reading the stores back, so it covers
    /// the routing itself rather than the bookkeeping around it.
    @Test func demoRecordsNeverReachTheRealLogStore() async throws {
        let logSystem = Periscope.isolated()
        let realLogStore = try await PeriscopeStore.make(storage: .inMemory, session: .current())
        let bootstrap = try ScriptedBootstrap(services: makeServices(), logStore: realLogStore)
        let model = WhereModel(
            preferences: makePreferences(),
            bootstrap: bootstrap,
            logSystem: logSystem,
        )

        // Log in for real, and wait for the durable store to be routing.
        let realScope = try await model.resolveScope()
        try await waitUntil { realScope.logStore != nil }
        Log<DemoProbeLog>(system: logSystem).info("before the demo")

        // Enter the demo: from here the real store must hear nothing.
        try await model.activateDemo(model.makeDemoScope())
        let demoStore = try #require(model.activeScope?.logStore)
        Log<DemoProbeLog>(system: logSystem).info("during the demo")
        await logSystem.flush()

        var real = try await messages(in: realLogStore)
        #expect(real.contains("before the demo"))
        #expect(!real.contains("during the demo"))
        #expect(try await messages(in: demoStore).contains("during the demo"))

        // And leaving hands the real store its records back.
        await model.deactivateDemo()
        Log<DemoProbeLog>(system: logSystem).info("after the demo")
        await logSystem.flush()
        real = try await messages(in: realLogStore)
        #expect(real.contains("after the demo"))
        #expect(try await !messages(in: demoStore).contains("after the demo"))
    }

    /// The regression the routing state machine exists for: a durable store
    /// that finishes opening *after* a demo has shadowed its scope must be
    /// recorded, never attached — otherwise the demo's records land on the
    /// user's disk. Reachable in the app when a failed backup restore opens the
    /// store and the user then taps into the demo.
    @Test func aLogStoreOpeningLateNeverAttachesToAShadowedScope() async throws {
        let logSystem = Periscope.isolated()
        let realLogStore = try await PeriscopeStore.make(storage: .inMemory, session: .current())
        let bootstrap = try ScriptedBootstrap(services: makeServices(), logStore: realLogStore)
        let model = WhereModel(
            preferences: makePreferences(),
            bootstrap: bootstrap,
            logSystem: logSystem,
        )
        bootstrap.gateLogStore()

        // Log in for real with the durable store held mid-open.
        let realScope = try await model.resolveScope()
        #expect(realScope.logStore == nil)

        try await model.activateDemo(model.makeDemoScope())
        bootstrap.releaseLogStore()
        try await waitUntil { realScope.logStore != nil }

        Log<DemoProbeLog>(system: logSystem).info("during the demo")
        await logSystem.flush()
        // The store arrived and is remembered, but nothing routed into it.
        #expect(try await !messages(in: realLogStore).contains("during the demo"))

        // Leaving resumes routing into the store that arrived while shadowed.
        await model.deactivateDemo()
        Log<DemoProbeLog>(system: logSystem).info("after the demo")
        await logSystem.flush()
        #expect(try await messages(in: realLogStore).contains("after the demo"))
    }

    private func messages(in store: PeriscopeStore) async throws -> [String] {
        try await store.events(matching: LogQuery()).map(\.message)
    }
}

/// A freeform probe event, so the routing tests can emit something they can
/// then look for in a specific store.
private struct DemoProbeLog: LogEvent {
    var message: String {
        ""
    }
}
