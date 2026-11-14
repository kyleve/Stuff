import Foundation
import Observation

/// One process-wide compatibility decision. Only full server verification can restore access;
/// a same-account, same-version receipt can preserve it during a transient outage.
@MainActor
@Observable
public final class DataCompatibilityCoordinator {
    public enum State {
        case checking
        case allowed
        case offline(any Error)
        case blocked(DataCompatibilityFailure)

        public var allowsStore: Bool {
            switch self {
                case .allowed, .offline: true
                case .checking, .blocked: false
            }
        }
    }

    public enum RecordingEligibility: Sendable {
        case recording(RecordingDeviceID)
        case disabled
        case permissionRequired
    }

    private struct Cloud {
        let transport: any DataCompatibilityTransport
        let receipts: any DataCompatibilityReceiptStoring
    }

    public private(set) var state: State
    public let version: DataModelVersion
    @ObservationIgnored public var onStateChange: @MainActor () -> Void = {}
    @ObservationIgnored private let cloud: Cloud?
    @ObservationIgnored private var verification: Task<Void, Never>?
    @ObservationIgnored private var accountObservation: Task<Void, Never>?
    @ObservationIgnored private var epoch: UInt64 = 0
    @ObservationIgnored private var knownVersion = DataModelVersion.baseline
    @ObservationIgnored private var removedDeviceID: RecordingDeviceID?
    private static let logger = WhereLog.root(DataCompatibilityLog.self)

    /// Local-only and in-memory worlds do not consult or publish CloudKit metadata.
    public init() {
        cloud = nil
        version = .current
        state = .allowed
    }

    public init(
        transport: any DataCompatibilityTransport,
        receipts: any DataCompatibilityReceiptStoring,
        version: DataModelVersion,
    ) {
        cloud = Cloud(transport: transport, receipts: receipts)
        self.version = version
        state = .checking
        accountObservation = Task { [weak self] in
            for await _ in transport.accountChanges() {
                guard !Task.isCancelled else { break }
                self?.invalidateAccount()
            }
        }
    }

    isolated deinit {
        accountObservation?.cancel()
        verification?.cancel()
    }

    public func refresh(
        recording: @escaping @MainActor () async throws -> RecordingEligibility,
    ) async {
        guard let cloud else { return }
        if let verification {
            await verification.value
            return
        }
        let epoch = epoch
        let task = Task { [weak self] in
            guard let self else { return }
            await Self.logger.measure(.verify, budget: .seconds(10)) {
                await self.verify(cloud, epoch: epoch, recording: recording)
            }
        }
        verification = task
        await task.value
        if self.epoch == epoch { verification = nil }
    }

    public func requireAccess() throws {
        switch state {
            case .allowed, .offline: return
            case .checking:
                throw DataCompatibilityFailure.verificationRequired(
                    DataCompatibilityTransportError.accountChanged,
                )
            case let .blocked(failure): throw failure
        }
    }

    public func recordRemoval(of deviceID: RecordingDeviceID) {
        removedDeviceID = deviceID
        guard let cloud else { return }
        do {
            if let receipt = try cloud.receipts.load() {
                try cloud.receipts.save(DataCompatibilityReceipt(
                    accountID: receipt.accountID,
                    version: receipt.version,
                    access: receipt.access,
                    removedDeviceID: deviceID,
                ))
            }
        } catch { fail(error) }
    }

    private func invalidateAccount() {
        epoch &+= 1
        verification?.cancel()
        verification = nil
        if let cloud {
            do {
                if let receipt = try cloud.receipts.load() {
                    knownVersion = max(knownVersion, receipt.version)
                    removedDeviceID = receipt.removedDeviceID
                    try save(cloud, accountID: receipt.accountID, access: .blocked)
                }
            } catch { Self.logger.verificationFailed(error: .restricted(.errorDetails, error)) }
        }
        fail(DataCompatibilityTransportError.accountChanged)
    }

    private func verify(
        _ cloud: Cloud,
        epoch: UInt64,
        recording: @escaping @MainActor () async throws -> RecordingEligibility,
    ) async {
        var accountID: DataCompatibilityAccountID?
        var prior: DataCompatibilityReceipt?
        do {
            prior = try cloud.receipts.load()
            if let prior {
                knownVersion = max(knownVersion, prior.version)
                removedDeviceID = prior.removedDeviceID
            }
            if knownVersion > version {
                set(.blocked(.updateRequired(knownVersion)))
                return
            }
            let account = try await cloud.transport.accountID()
            try checkEpoch(epoch)
            accountID = account
            if prior?.accountID != account { prior = nil }
            // Conflicting writers are bounded: later triggers retry if contention persists.
            for _ in 0 ..< 3 {
                let remote = try await cloud.transport.read(accountID: account)
                try checkEpoch(epoch)
                let sharedVersion = remote?.version ?? .baseline
                knownVersion = max(knownVersion, sharedVersion)
                if knownVersion > version {
                    try save(cloud, accountID: account, access: .blocked)
                    set(.blocked(.updateRequired(knownVersion)))
                    return
                }
                let eligibility = try await recording()
                try checkEpoch(epoch)
                let canPublish: Bool = switch eligibility {
                    case let .recording(deviceID): deviceID != removedDeviceID
                    case .disabled, .permissionRequired: false
                }
                if sharedVersion < version, !canPublish {
                    try save(cloud, accountID: account, access: .blocked)
                    if case .permissionRequired = eligibility {
                        set(.blocked(.locationPermissionRequired))
                    } else {
                        set(.blocked(.recordingDeviceRequired))
                    }
                    return
                }
                if sharedVersion < version || (remote == nil && canPublish) {
                    do {
                        let saved = try await cloud.transport.advance(
                            accountID: account,
                            from: remote,
                            to: version,
                        )
                        try checkEpoch(epoch)
                        knownVersion = max(knownVersion, saved.version)
                        // A competing newer writer can win while the save is in flight.
                        guard knownVersion == version else { continue }
                    } catch DataCompatibilityTransportError.conflict { continue }
                }
                try checkEpoch(epoch)
                try save(cloud, accountID: account, access: .verified)
                set(.allowed)
                return
            }
            throw DataCompatibilityTransportError.conflict
        } catch is CancellationError {
            return
        } catch {
            guard self.epoch == epoch else { return }
            if case DataCompatibilityTransportError.unavailable = error,
               let prior, prior.accountID == accountID, prior.access == .verified,
               prior.version == version, knownVersion == version
            {
                Self.logger.verificationFailed(error: .restricted(.errorDetails, error))
                set(.offline(error))
            } else {
                // Persist withdrawal so a separate share process cannot trust an obsolete grant.
                if let account = accountID ?? prior?.accountID {
                    do { try save(cloud, accountID: account, access: .blocked) }
                    catch {
                        Self.logger.verificationFailed(error: .restricted(.errorDetails, error))
                    }
                }
                fail(error)
            }
        }
    }

    private func save(
        _ cloud: Cloud,
        accountID: DataCompatibilityAccountID,
        access: DataCompatibilityReceipt.Access,
    ) throws {
        try cloud.receipts.save(DataCompatibilityReceipt(
            accountID: accountID,
            version: knownVersion,
            access: access,
            removedDeviceID: removedDeviceID,
        ))
    }

    private func checkEpoch(_ expected: UInt64) throws {
        try Task.checkCancellation()
        guard epoch == expected else { throw CancellationError() }
    }

    private func fail(_ error: any Error) {
        Self.logger.verificationFailed(error: .restricted(.errorDetails, error))
        set(.blocked(.verificationRequired(error)))
    }

    private func set(_ state: State) {
        self.state = state
        if case let .blocked(failure) = state {
            Self.logger.blocked(reason: .restricted(.technicalState, String(describing: failure)))
        }
        onStateChange()
    }
}
