import Foundation

/// Evaluates the global boot contract over the one store and existing recording authority.
public actor DataCompatibilityCoordinator {
    private let store: any WhereStore
    private let recording: RecordingDeviceCoordination
    private let installation: any InstallationRecordingContextStoring
    private let supportedVersion: DataCompatibilityVersion
    private var permit: DataAccessPermit?
    private var checking: Task<DataCompatibilityState, Never>?
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

    public func recheck() async -> DataCompatibilityState {
        await recording.subscribeToChanges()
        return await check(refreshAuthority: true)
    }

    /// Local history changes need no network round trip. A prior verification failure
    /// remains blocked until an explicit remote retry succeeds.
    public func recheckLocalHistory() async -> DataCompatibilityState {
        do {
            let required = try await store.requiredDataCompatibilityVersion()
            if required > supportedVersion {
                state = .updateRequired(required)
                revokeAccess()
                return state
            }
        } catch {
            Self.logger(attachments: [.error(error, name: "local-compatibility-error")]) {
                .accessBlocked(description: error.localizedDescription)
            }
            state = .verificationFailed(error.localizedDescription)
            revokeAccess()
            return state
        }
        if case .verificationFailed = state { return state }
        if checking != nil { return state }
        return await check(refreshAuthority: false)
    }

    private func check(refreshAuthority: Bool) async -> DataCompatibilityState {
        if let checking { return await checking.value }
        let task = Task {
            let result = await self.evaluate(refreshAuthority: refreshAuthority)
            // A locally observed higher floor cannot be undone by an older remote completion.
            if case .updateRequired = self.state {} else { self.state = result }
            _ = await self.recheckLocalHistory()
            if case .compatible = self.state {} else { self.revokeAccess() }
            self.checking = nil
            return self.state
        }
        checking = task
        return await task.value
    }

    public func revokeAccess() {
        permit?.revoke()
        permit = nil
    }

    /// Each normal world receives a new permit; stale worlds can never regain access.
    public func openDomainStore() async throws -> any WhereStore {
        let required = try await store.requiredDataCompatibilityVersion()
        guard case let .compatible(version) = state,
              version == supportedVersion,
              required == version
        else { throw DataCompatibilityError.notReady }
        revokeAccess()
        let permit = DataAccessPermit()
        self.permit = permit
        return CompatibilityScopedStore(base: store, permit: permit)
    }

    private func evaluate(refreshAuthority: Bool) async -> DataCompatibilityState {
        do {
            await recording.waitUntilIdle()
            let authority = try await (refreshAuthority ? recording.refreshForUse() : recording
                .observed())
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
                try await recording.advanceCompatibility()
            }
            let verified = try await store.requiredDataCompatibilityVersion()
            guard verified == supportedVersion else {
                return verified > supportedVersion ? .updateRequired(verified) :
                    .verificationFailed("The shared version did not advance.")
            }
            return .compatible(verified)
        } catch {
            Self.logger(attachments: [.error(error, name: "compatibility-error")]) {
                .accessBlocked(description: error.localizedDescription)
            }
            return .verificationFailed(error.localizedDescription)
        }
    }

    private static let logger = WhereLog.root(DataCompatibilityLog.self)
}
