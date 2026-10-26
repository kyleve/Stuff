import Foundation

/// Evaluates the global boot contract over the one store and existing recording authority.
public actor DataCompatibilityCoordinator: DataCompatibilityChecking {
    private let store: any WhereStore
    private let recording: RecordingDeviceCoordination
    private let installation: any InstallationRecordingContextStoring
    private let supportedVersion: DataCompatibilityVersion
    private var permit: DataAccessPermit?
    private enum Verification {
        case localHistory, remoteAuthority
    }

    private struct Check {
        let verification: Verification
        let task: Task<DataCompatibilityState, Never>
    }

    private struct AccountSession: Equatable { let id = UUID() }
    private var accountSession = AccountSession()
    private var checking: Check?
    private var invalidating: Task<Void, Never>?
    #if DEBUG
        /// Counts admitted checks so race tests can hold a local check before a remote caller
        /// joins.
        @_spi(Testing) public private(set) var pendingCheckCountForTesting = 0
    #endif
    private var stateRevision: UInt64 = 0
    private var state: DataCompatibilityState = .checking {
        didSet { if oldValue != state { stateRevision &+= 1 } }
    }

    public func snapshot() -> DataCompatibilitySnapshot {
        .init(revision: stateRevision, state: state)
    }

    public init(
        store: any WhereStore,
        recording: RecordingDeviceCoordination,
        installation: any InstallationRecordingContextStoring,
    ) {
        self.store = store
        self.recording = recording
        self.installation = installation
        supportedVersion = recording.supportedVersion
    }

    public nonisolated func changes() -> AsyncStream<Void> {
        store.changes()
    }

    /// Revoke before touching persistence or the network. Old completions retain their old token.
    public func invalidateAccount() async {
        accountSession = AccountSession()
        checking?.task.cancel()
        checking = nil
        revokeAccess()
        if case .updateRequired = state {} else {
            state = .verificationFailed(.init(RecordingAccountError.verificationRequired))
        }
        let session = accountSession
        let task = Task {
            do { try await self.recording.invalidateAccount() }
            catch {
                Self.logger.accessBlocked(error: .restricted(.errorDetails, error))
                guard session == self.accountSession else { return }
                self.state = .verificationFailed(.init(error))
            }
        }
        invalidating = task
        await task.value
        if session == accountSession { invalidating = nil }
    }

    public func recheck() async -> DataCompatibilityState {
        let session = accountSession
        await invalidating?.value
        guard session == accountSession else { return state }
        await recording.subscribeToChanges()
        guard session == accountSession else { return state }
        return await check(.remoteAuthority)
    }

    /// Local history changes need no network round trip. A prior verification failure
    /// remains blocked until an explicit remote retry succeeds.
    public func recheckLocalHistory() async -> DataCompatibilityState {
        let session = accountSession
        do {
            let required = try await store.requiredDataCompatibilityVersion()
            guard session == accountSession else { return state }
            if required > supportedVersion {
                state = .updateRequired(required)
                revokeAccess()
                return state
            }
        } catch {
            guard session == accountSession else { return state }
            Self.logger.accessBlocked(error: .restricted(.errorDetails, error))
            state = .verificationFailed(.init(error))
            revokeAccess()
            return state
        }
        if case .verificationFailed = state { return state }
        if checking != nil { return state }
        return await check(.localHistory)
    }

    private func check(_ verification: Verification) async -> DataCompatibilityState {
        #if DEBUG
            pendingCheckCountForTesting += 1
            defer { pendingCheckCountForTesting -= 1 }
        #endif
        let session = accountSession
        if let checking {
            let result = await checking.task.value
            guard session == accountSession else { return state }
            if verification == .remoteAuthority, checking.verification == .localHistory {
                // Re-enter after the local task: another queued caller may already own this read.
                return await check(.remoteAuthority)
            }
            return result
        }
        let task = Task {
            let result = await self.evaluate(verification)
            guard session == self.accountSession else { return self.state }
            // A locally observed higher floor cannot be undone by an older remote completion.
            if case .updateRequired = self.state {} else { self.state = result }
            _ = await self.recheckLocalHistory()
            guard session == self.accountSession else { return self.state }
            if case .compatible = self.state {} else { self.revokeAccess() }
            self.checking = nil
            return self.state
        }
        checking = Check(verification: verification, task: task)
        return await task.value
    }

    public func revokeAccess() {
        permit?.revoke()
        permit = nil
    }

    /// Each normal world receives a new permit; stale worlds can never regain access.
    public func openDomainStore() async throws -> CompatibilityScopedStore {
        let session = accountSession
        let required = try await store.requiredDataCompatibilityVersion()
        guard invalidating == nil, session == accountSession, case let .compatible(version) = state,
              version == supportedVersion,
              required == version
        else { throw DataCompatibilityError.notReady }
        revokeAccess()
        let permit = DataAccessPermit()
        self.permit = permit
        return CompatibilityScopedStore(base: store, permit: permit)
    }

    public func retireScope(_ services: WhereServices) async {
        revokeAccess()
        await services.suspendForCompatibility()
    }

    /// Demo and test worlds own a new memory-only store. They cannot authorize an existing
    /// durable store or bypass account verification for one.
    @_spi(Demo) @_spi(Testing)
    public static func isolatedDomainStore() throws -> CompatibilityScopedStore {
        try CompatibilityScopedStore(base: SwiftDataStore.inMemory(), permit: DataAccessPermit())
    }

    private func evaluate(_ verification: Verification) async -> DataCompatibilityState {
        do {
            await recording.waitUntilIdle()
            let authority: RecordingAuthority = switch verification {
                case .localHistory: try await recording.observed()
                case .remoteAuthority: try await recording.refreshForUse()
            }
            let required = try await store.requiredDataCompatibilityVersion()
            guard supportedVersion >= required else { return .updateRequired(required) }
            let context = try await installation.resolve()
            guard context.recordingControl.selection != .unconfirmed
            else { return .recordingChoiceRequired }
            if supportedVersion > required {
                guard let owner = authority.owner else { return .recordingChoiceRequired }
                guard owner.deviceID == context.currentDevice.id
                else { return .waitingForRecordingDevice(owner) }
                // No offline or secondary override: this always rechecks and commits on the server.
                try Task.checkCancellation()
                try await recording.advanceCompatibility()
            }
            let verified = try await store.requiredDataCompatibilityVersion()
            guard verified == supportedVersion else {
                return verified > supportedVersion ? .updateRequired(verified) :
                    .verificationFailed(.init(DataCompatibilityFailure.UnchangedRequirement(
                        expected: supportedVersion,
                        observed: verified,
                    )))
            }
            return .compatible(verified)
        } catch {
            Self.logger.accessBlocked(error: .restricted(.errorDetails, error))
            return .verificationFailed(.init(error))
        }
    }

    private static let logger = WhereLog.root(DataCompatibilityLog.self)
}
