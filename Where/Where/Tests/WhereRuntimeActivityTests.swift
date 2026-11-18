import Foundation
import LifecycleKit
import PeriscopeCore
import Testing
@testable import Where
@_spi(Testing) import WhereCore
@_spi(Testing) import WhereUI

@MainActor
struct WhereRuntimeActivityTests {
    @Test func inactiveInputPreservesTheHeadlessRunner() async throws {
        let fixture = try RuntimeActivityFixture(reason: .undetermined)
        fixture.runtime.sceneActivityChanged(isActive: false)
        await fixture.runtime.waitForSceneActivityForTesting()
        #expect(fixture.launcher.reason == .undetermined)
        #expect(await fixture.transport.readCount == 0)
        #expect(await fixture.source.authorizationReadCount == 0)
    }

    @Test func activeThenInactiveBeforeTheTaskStartsDoesNotPromote() async throws {
        let fixture = try RuntimeActivityFixture(reason: .undetermined)
        fixture.runtime.sceneActivityChanged(isActive: true)
        fixture.runtime.sceneActivityChanged(isActive: false)
        await fixture.runtime.waitForSceneActivityForTesting()
        #expect(fixture.launcher.reason == .undetermined)
        #expect(await fixture.transport.readCount == 0)
        #expect(await fixture.source.authorizationReadCount == 0)
    }

    @Test func activeInputPromotesLaunchAndDuplicateInputDoesNotActivateAgain() async throws {
        let fixture = try RuntimeActivityFixture(reason: .undetermined)
        await fixture.launcher.run()
        let before = await fixture.source.authorizationReadCount
        fixture.runtime.sceneActivityChanged(isActive: true)
        defer { fixture.runtime.sceneActivityChanged(isActive: false) }
        await fixture.runtime.waitForSceneActivityForTesting()
        #expect(fixture.launcher.reason == .userForeground)
        #expect(fixture.model.compatibility.isBlocking(fixture.model) == false)
        let activated = await fixture.source.authorizationReadCount
        #expect(activated > before)

        fixture.runtime.sceneActivityChanged(isActive: true)
        await fixture.runtime.waitForSceneActivityForTesting()
        #expect(await fixture.source.authorizationReadCount == activated)

        fixture.runtime.sceneActivityChanged(isActive: false)
        fixture.runtime.sceneActivityChanged(isActive: true)
        await fixture.runtime.waitForSceneActivityForTesting()
        #expect(await fixture.source.authorizationReadCount > activated)
    }

    @Test func inactiveInputSuppressesActivationAfterHeldVerificationFinishes() async throws {
        let fixture = try RuntimeActivityFixture(reason: .userForeground)
        await fixture.launcher.run()
        let before = await fixture.source.authorizationReadCount
        await fixture.transport.holdNextRead()
        fixture.runtime.sceneActivityChanged(isActive: true)
        try await waitForRuntimeCondition { await fixture.transport.isReadHeld }
        fixture.runtime.sceneActivityChanged(isActive: false)
        await fixture.transport.releaseRead()
        await fixture.runtime.waitForSceneActivityForTesting()
        #expect(await fixture.source.authorizationReadCount == before)
        #expect(fixture.model.compatibility.coordinator.state.allowsStore)
    }

    @Test func incompatibleForegroundRefreshNeverActivatesTheOldSession() async throws {
        let fixture = try RuntimeActivityFixture(reason: .userForeground)
        await fixture.launcher.run()
        let before = await fixture.source.authorizationReadCount
        await fixture.transport.setVersion(.init(rawValue: 2))
        fixture.runtime.sceneActivityChanged(isActive: true)
        defer { fixture.runtime.sceneActivityChanged(isActive: false) }
        await fixture.runtime.waitForSceneActivityForTesting()
        #expect(fixture.model.compatibility.isBlocking(fixture.model))
        #expect(await fixture.source.authorizationReadCount == before)
    }

    @Test func inactiveInputStopsForegroundPolling() async throws {
        let fixture = try RuntimeActivityFixture(reason: .userForeground)
        await fixture.launcher.run()
        let clock = RuntimeActivityPollClock()
        fixture.model.compatibility.setPollWait { try await clock.wait() }
        fixture.runtime.sceneActivityChanged(isActive: true)
        defer { fixture.runtime.sceneActivityChanged(isActive: false) }
        try await waitForRuntimeCondition { await clock.waitCount == 1 }
        await fixture.runtime.waitForSceneActivityForTesting()
        fixture.runtime.sceneActivityChanged(isActive: false)
        try await waitForRuntimeCondition { await clock.cancellationCount == 1 }
    }
}

@MainActor
private struct RuntimeActivityFixture {
    let runtime: RegularApplicationRuntime
    let model: WhereModel
    let launcher: LifecycleRunner<WhereSession>
    let source = RuntimeActivityLocationSource()
    let transport = RuntimeActivityTransport()

    init(reason: LifecycleReason) throws {
        let preferences = WherePreferences(store: InMemoryKeyValueStore())
        preferences.hasOnboarded = true
        let services = try WhereServices(
            store: SwiftDataStore.inMemory(),
            locationSource: source,
            reminderScheduler: NoopLoggingReminderScheduler(),
            summaryScheduler: NoopDailySummaryScheduler(),
            issueAlertScheduler: NoopDataIssueAlertScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
        )
        model = WhereModel(
            services: services,
            preferences: preferences,
            logSystem: Periscope(configuration: .init(), sinks: []),
            compatibility: .init(coordinator: .init(
                transport: transport,
                receipts: InMemoryDataCompatibilityReceiptStore(receipt: nil),
                version: .baseline,
            )),
            installationLocation: .init(makeSource: { ScriptedLocationSource() }),
        )
        launcher = WhereLaunch.makeLauncher(model: model, reason: reason)
        runtime = RegularApplicationRuntime(
            forTesting: model,
            launcher: launcher,
            buildEnvironment: .init(
                audience: .development,
                appGroupIdentifier: "group.com.stuff.where.tests",
                primaryAppIconName: "AppIcon",
                isRunningTests: true,
            ),
        )
    }
}

private actor RuntimeActivityLocationSource: LocationSource {
    nonisolated let sampleStream = AsyncStream<LocationSample> { $0.finish() }
    nonisolated let authorizationUpdates = AsyncStream<LocationAuthorizationStatus> { $0.finish() }
    private(set) var authorizationReadCount = 0

    func currentAuthorization() -> LocationAuthorizationStatus {
        authorizationReadCount += 1
        return .always
    }

    func start() {}
    func stop() {}
    func requestPermission() {}
    func requestCurrentLocation() -> CurrentLocationResult {
        .unavailable(.timeout)
    }
}

private actor RuntimeActivityTransport: DataCompatibilityTransport {
    private var version = DataModelVersion.baseline
    private var shouldHoldRead = false
    private var readContinuation: CheckedContinuation<Void, Never>?
    private(set) var readCount = 0
    var isReadHeld: Bool {
        readContinuation != nil
    }

    func domain() -> DataCompatibilityDomain {
        .local
    }

    func read(domain _: DataCompatibilityDomain) async -> PersistedDataModelVersion? {
        readCount += 1
        if shouldHoldRead {
            shouldHoldRead = false
            // Deliberately finishes after caller cancellation to exercise the runtime's guard.
            await withCheckedContinuation { readContinuation = $0 }
        }
        return .init(version: version, revision: "local")
    }

    func advance(
        domain _: DataCompatibilityDomain,
        from _: PersistedDataModelVersion?,
        to _: DataModelVersion,
    ) throws -> PersistedDataModelVersion {
        throw DataCompatibilityTransportError.invalidRecord
    }

    nonisolated func accountChanges() -> AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }

    func holdNextRead() {
        shouldHoldRead = true
    }

    func setVersion(_ value: DataModelVersion) {
        version = value
    }

    func releaseRead() {
        readContinuation?.resume()
        readContinuation = nil
    }
}

private struct RuntimeActivityTimeout: Error {}

private actor RuntimeActivityPollClock {
    private(set) var waitCount = 0
    private(set) var cancellationCount = 0

    func wait() async throws {
        waitCount += 1
        do { try await Task.sleep(for: .seconds(3600)) }
        catch {
            cancellationCount += 1
            throw error
        }
    }
}

@MainActor
private func waitForRuntimeCondition(_ condition: () async -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while await !condition() {
        guard ContinuousClock.now < deadline else { throw RuntimeActivityTimeout() }
        try await Task.sleep(for: .milliseconds(1))
    }
}
