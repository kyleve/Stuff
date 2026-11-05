import Foundation
import PeriscopeCore
@_spi(Testing) import WhereCore
@testable import WhereUI

/// Uses real scoped services and a controllable shared-account response without platform I/O.
@MainActor
final class CompatibilityLaunchFixture: WhereScopeAssembling {
    struct WaitTimeout: Error {}

    static func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !predicate() {
            guard ContinuousClock.now < deadline else { throw WaitTimeout() }
            await Task.yield()
        }
    }

    let store: SwiftDataStore
    let transport = CompatibilityLaunchTransport()
    let coordinator: DataCompatibilityCoordinator
    let installation = makeInstallationRecordingContextStore(setup: .complete)
    private(set) var assemblyCount = 0
    private(set) var withdrawalCount = 0
    private(set) var services: WhereServices?
    var sharedDrafts: (any SharedEvidenceDraftQueuing)?
    var beforeAssembly: @MainActor () async -> Void = {}
    var makeLocationSource: @MainActor () -> any LocationSource = {
        ScriptedLocationSource(authorizationStatus: .always)
    }

    init() throws {
        store = try SwiftDataStore.inMemory()
        coordinator = DataCompatibilityCoordinator(
            store: store,
            source: .cloudKit(
                storeID: .init(rawValue: "launch-fixture"),
                transport: transport,
                cache: InMemoryDataCompatibilityCache(value: nil),
            ),
            policy: .foundation,
            activationReadiness: .pendingValidation,
        )
    }

    func makeModel() -> WhereModel {
        let preferences = makePreferences()
        preferences.hasOnboarded = true
        return WhereModel(
            preferences: preferences,
            installationContextStore: installation,
            makeBootstrap: { _ in self },
            logSystem: .isolated(),
        )
    }

    func sharedEvidenceDraftQueue() -> (any SharedEvidenceDraftQueuing)? {
        sharedDrafts
    }

    func prepareDataCompatibility() -> DataCompatibilityCoordinator? {
        coordinator
    }

    func prepareLocation() {}
    func makeLogStore() async throws -> PeriscopeStore? {
        nil
    }

    func discoverRecordingDevices() async throws -> [RecordingDevice] {
        let access = try await coordinator.refresh()
        return try await access.store.recordingDevices()
    }

    func makeServices() async throws -> WhereServices {
        if let services { await services.retireCompatibilityScope() }
        let access = try await coordinator.refresh()
        await beforeAssembly()
        try access.validate()
        let next = try await WhereServices.make(
            access: access,
            locationSource: makeLocationSource(),
            installationContext: installation.resolve(),
            aggregator: DayAggregator(),
            reminderScheduler: NoopEveningReminderScheduler(),
            summaryScheduler: NoopDailySummaryScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
            locationOutbox: NoOpLocationOutbox(),
            importRecoveryPersistence: installation,
            now: Date.init,
        )
        assemblyCount += 1
        services = next
        return next
    }

    func withdrawHistoryOutputs() async {
        withdrawalCount += 1
        await services?.retireCompatibilityScope()
    }
}

actor CompatibilityLaunchTransport: SharedDataCompatibilityTransport {
    struct Offline: Error, Equatable {}
    private let account = DataCompatibilityAccountID(rawValue: "launch-account")
    private var result: Result<UInt, any Error> = .success(0)
    private(set) var verificationCount = 0
    private var verificationHold: CompatibilityLaunchSuspension?

    func holdVerification(_ hold: CompatibilityLaunchSuspension) {
        verificationHold = hold
    }

    func setResult(_ result: Result<UInt, any Error>) {
        self.result = result
    }

    func accountID() async throws -> DataCompatibilityAccountID {
        account
    }

    func verify(accountID: DataCompatibilityAccountID) async throws
        -> SharedDataCompatibilityVerification
    {
        verificationCount += 1
        if let hold = verificationHold {
            verificationHold = nil
            await hold.suspend()
        }
        return try .init(accountID: accountID, history: .existing(.init(
            accountID: accountID,
            requiredMajor: result.get(),
            revision: .init(rawValue: "fixture"),
        )))
    }

    func initialize(accountID _: DataCompatibilityAccountID, newAccountMajor _: UInt) async throws
        -> SharedDataCompatibilityState
    {
        throw DataCompatibilityError.concurrentChange
    }

    func advance(from _: SharedDataCompatibilityState, to _: UInt) async throws
        -> SharedDataCompatibilityState
    {
        throw DataCompatibilityError.concurrentChange
    }

    nonisolated func accountChanges() -> AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }
}

/// Holds a launch handoff so promotion and retirement can race at a known suspension.
@MainActor
final class CompatibilityLaunchSuspension {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var entered = false
    private var released = false

    func suspend() async {
        guard !released else { return }
        await withCheckedContinuation {
            continuation = $0
            entered = true
        }
    }

    func resume() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}
