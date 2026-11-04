import CloudKit
import Foundation
@testable import WhereCore

actor ScriptedSharedDataCompatibilityTransport: SharedDataCompatibilityTransport {
    static let account = DataCompatibilityAccountID(rawValue: "test-account")
    private var currentAccount = account
    private var history: SharedDataCompatibilityVerification.History
    private var verificationError: (any Error)?
    private var identityError: (any Error)?
    private var advanceResponseError: (any Error)?
    private var verifyGate: CompatibilityTestGate?
    private var advanceGate: CompatibilityTestGate?
    private var nextRevision = 1
    private(set) var creations = 0
    private(set) var advances = 0
    private let events: AsyncStream<Void>
    private let eventContinuation: AsyncStream<Void>.Continuation

    init(history: SharedDataCompatibilityVerification.History) {
        self.history = history
        (events, eventContinuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    func accountID() async throws -> DataCompatibilityAccountID {
        if let identityError { throw identityError }
        return currentAccount
    }

    func verify(accountID: DataCompatibilityAccountID) async throws
        -> SharedDataCompatibilityVerification
    {
        guard accountID == currentAccount else { throw DataCompatibilityError.accountChanged }
        let result = SharedDataCompatibilityVerification(accountID: accountID, history: history)
        let heldGate = verifyGate
        verifyGate = nil
        if let heldGate { await heldGate.suspend() }
        if let verificationError { throw verificationError }
        return result
    }

    func initialize(accountID: DataCompatibilityAccountID, newAccountMajor: UInt) async throws
        -> SharedDataCompatibilityState
    {
        guard accountID == currentAccount else { throw DataCompatibilityError.accountChanged }
        let major: UInt
        switch history {
            case let .existing(value): return value
            case .legacyAccount: major = 0
            case .newAccount: major = newAccountMajor
        }
        creations += 1
        let value = makeState(major: major)
        history = .existing(value)
        return value
    }

    func advance(from expected: SharedDataCompatibilityState, to requiredMajor: UInt) async throws
        -> SharedDataCompatibilityState
    {
        if let advanceGate { await advanceGate.suspend() }
        guard case let .existing(current) = history, current == expected,
              currentAccount == expected.accountID, requiredMajor >= current.requiredMajor
        else { throw DataCompatibilityError.concurrentChange }
        advances += 1
        let value = makeState(major: requiredMajor)
        history = .existing(value)
        if let advanceResponseError { throw advanceResponseError }
        return value
    }

    nonisolated func accountChanges() -> AsyncStream<Void> {
        events
    }

    func loseAdvanceResponse(_ error: any Error) {
        advanceResponseError = error
    }

    func failVerification(_ error: (any Error)?) {
        verificationError = error
    }

    func failIdentity(_ error: (any Error)?) {
        identityError = error
    }

    func holdNextVerification(_ gate: CompatibilityTestGate) {
        verifyGate = gate
    }

    func holdAdvance(_ gate: CompatibilityTestGate) {
        advanceGate = gate
    }

    func changeAccount() {
        currentAccount = .init(rawValue: "different-account")
        eventContinuation.yield()
    }

    func establish(major: UInt) {
        history = .existing(makeState(major: major))
    }

    private func makeState(major: UInt) -> SharedDataCompatibilityState {
        defer { nextRevision += 1 }
        return .init(
            accountID: currentAccount,
            requiredMajor: major,
            revision: .init(rawValue: String(nextRevision)),
        )
    }
}

enum DataCompatibilityTestSupport {
    struct WaitTimeout: Error {}

    @MainActor static func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !predicate() {
            guard ContinuousClock.now < deadline else { throw WaitTimeout() }
            await Task.yield()
        }
    }

    static let storeID = DataCompatibilityDataset.StoreID(rawValue: "test-store")
    static let policy = DataCompatibilityPolicy(
        current: .init(major: 1, minor: 3, patch: 4),
        supportedMajors: [0, 1],
    )

    static func state(major: UInt) -> SharedDataCompatibilityState {
        .init(
            accountID: ScriptedSharedDataCompatibilityTransport.account,
            requiredMajor: major,
            revision: .init(rawValue: "initial"),
        )
    }

    @MainActor static func coordinator(
        store: any WhereStore,
        transport: ScriptedSharedDataCompatibilityTransport,
        cache: any DataCompatibilityCacheStoring,
    ) -> DataCompatibilityCoordinator {
        .init(
            store: store,
            source: .cloudKit(storeID: storeID, transport: transport, cache: cache),
            policy: policy,
            activationReadiness: .ready,
        )
    }
}

@MainActor
final class FailingDataCompatibilityCache: DataCompatibilityCacheStoring {
    struct WriteFailure: Error {}
    private let value: DataCompatibilityCache
    init(value: DataCompatibilityCache) {
        self.value = value
    }

    func load() throws -> DataCompatibilityCache? {
        value
    }

    func save(_: DataCompatibilityCache) throws {
        throw WriteFailure()
    }
}

@MainActor
final class ScriptedDataCompatibilityCache: DataCompatibilityCacheStoring {
    struct WriteFailure: Error {}
    private var value: DataCompatibilityCache?
    var rejectedMajor: UInt?
    init(value: DataCompatibilityCache?) {
        self.value = value
    }

    func load() throws -> DataCompatibilityCache? {
        value
    }

    func save(_ value: DataCompatibilityCache) throws {
        if let rejectedMajor, value.requiredMajor >= rejectedMajor { throw WriteFailure() }
        self.value = value
    }
}
