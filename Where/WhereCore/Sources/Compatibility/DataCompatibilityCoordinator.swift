import Foundation
import Observation

/// One process-wide decision, backed by explicit local or cloud transport and durable evidence.
@MainActor
@Observable
public final class DataCompatibilityCoordinator {
    public enum State {
        case checking
        case allowed(DataCompatibilityAdmission)
        case offline(DataCompatibilityAdmission, any Error)
        case blocked(DataCompatibilityFailure)

        public var admission: DataCompatibilityAdmission? {
            switch self {
                case let .allowed(admission), let .offline(admission, _): admission
                case .checking, .blocked: nil
            }
        }

        public var allowsStore: Bool {
            admission != nil
        }
    }

    public enum RecordingEligibility: Sendable {
        case recording(RecordingDeviceID)
        case disabled
        case permissionRequired
    }

    private struct VersionFloor {
        var version = DataModelVersion.baseline
        var changeReason: DataModelChangeReason?

        mutating func observe(_ version: DataModelVersion, reason: DataModelChangeReason?) {
            if version > self.version {
                self = Self(version: version, changeReason: reason)
            } else if version == self.version, let reason {
                changeReason = reason
            }
        }
    }

    public private(set) var state = State.checking
    public let version: DataModelVersion
    @ObservationIgnored public var onStateChange: @MainActor () -> Void = {}
    @ObservationIgnored private let transport: any DataCompatibilityTransport
    @ObservationIgnored private let receipts: any DataCompatibilityReceiptStoring
    @ObservationIgnored private var verification: Task<Void, Never>?
    @ObservationIgnored private var accountObservation: Task<Void, Never>?
    @ObservationIgnored private var epoch: UInt64 = 0
    @ObservationIgnored private var versionFloor = VersionFloor()
    @ObservationIgnored private var removedDeviceID: RecordingDeviceID?
    private static let logger = WhereLog.root(DataCompatibilityLog.self)

    /// Isolated local worlds still pass through verification. App installations use durable
    /// receipts.
    public static func local(version: DataModelVersion) -> DataCompatibilityCoordinator {
        DataCompatibilityCoordinator(
            transport: LocalDataCompatibilityTransport(version: version),
            receipts: InMemoryDataCompatibilityReceiptStore(receipt: nil),
            version: version,
        )
    }

    public init(
        transport: any DataCompatibilityTransport,
        receipts: any DataCompatibilityReceiptStoring,
        version: DataModelVersion,
    ) {
        self.transport = transport
        self.receipts = receipts
        self.version = version
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
        if let verification {
            await verification.value
            return
        }
        let epoch = epoch
        let task = Task { [weak self] in
            guard let self else { return }
            await Self.logger.measure(.verify, budget: .seconds(10)) {
                await self.verify(epoch: epoch, recording: recording)
            }
        }
        verification = task
        await task.value
        if self.epoch == epoch { verification = nil }
    }

    public func onboardingReviewContext() throws -> OnboardingReviewContext {
        if case .blocked(.recordingDeviceRequired) = state, let receipt = try receipts.load() {
            return OnboardingReviewContext(domain: receipt.domain, epoch: epoch)
        }
        return try requireAccess().reviewContext
    }

    @discardableResult
    public func requireAccess() throws -> DataCompatibilityAdmission {
        switch state {
            case let .allowed(admission), let .offline(admission, _): return admission
            case .checking:
                throw DataCompatibilityFailure.verificationRequired(
                    DataCompatibilityTransportError.accountChanged,
                )
            case let .blocked(failure): throw failure
        }
    }

    public func requireAccess(_ admission: DataCompatibilityAdmission) throws {
        guard try requireAccess() == admission else {
            throw DataCompatibilityFailure.verificationRequired(
                DataCompatibilityTransportError.accountChanged,
            )
        }
    }

    public func recordRemoval(of deviceID: RecordingDeviceID) {
        removedDeviceID = deviceID
        do {
            if let receipt = try receipts.load() {
                try receipts.save(DataCompatibilityReceipt(
                    domain: receipt.domain,
                    version: receipt.version,
                    access: receipt.access,
                    removedDeviceID: deviceID,
                    changeReason: receipt.changeReason,
                ))
            }
        } catch { fail(error) }
    }

    private func invalidateAccount() {
        revokeAdmission()
        do {
            if let receipt = try receipts.load() {
                versionFloor.observe(receipt.version, reason: receipt.changeReason)
                removedDeviceID = receipt.removedDeviceID
                try save(domain: receipt.domain, access: .blocked)
            }
        } catch { Self.logger.verificationFailed(error: .restricted(.errorDetails, error)) }
        fail(DataCompatibilityTransportError.accountChanged)
    }

    private func revokeAdmission() {
        epoch &+= 1
        verification?.cancel()
        verification = nil
    }

    private func verify(
        epoch: UInt64,
        recording: @escaping @MainActor () async throws -> RecordingEligibility,
    ) async {
        var domain: DataCompatibilityDomain?
        var prior: DataCompatibilityReceipt?
        do {
            prior = try receipts.load()
            if let prior {
                versionFloor.observe(prior.version, reason: prior.changeReason)
                removedDeviceID = prior.removedDeviceID
            }
            if versionFloor.version > version {
                if let prior { try save(domain: prior.domain, access: .blocked) }
                blockForUpdate()
                return
            }
            let currentDomain = try await transport.domain()
            try checkEpoch(epoch)
            domain = currentDomain
            // A refresh may discover an account change before CKAccountChanged arrives. Revoke
            // the old scope first; a later verification can admit the replacement container.
            if let admission = state.admission, admission.domain != currentDomain {
                invalidateAccount()
                return
            }
            if prior?.domain != currentDomain { prior = nil }
            // Conflicting writers are bounded: later triggers retry if contention persists.
            for _ in 0 ..< 3 {
                let persisted = try await transport.read(domain: currentDomain)
                try checkEpoch(epoch)
                let persistedVersion = persisted?.version ?? .baseline
                versionFloor.observe(persistedVersion, reason: persisted?.changeReason)
                if versionFloor.version > version {
                    try save(domain: currentDomain, access: .blocked)
                    blockForUpdate()
                    return
                }
                let eligibility = try await recording()
                try checkEpoch(epoch)
                let canPublish: Bool = switch eligibility {
                    case let .recording(deviceID): deviceID != removedDeviceID
                    case .disabled, .permissionRequired: false
                }
                if persistedVersion < version, !canPublish {
                    try save(domain: currentDomain, access: .blocked)
                    if case .permissionRequired = eligibility {
                        set(.blocked(.locationPermissionRequired))
                    } else {
                        set(.blocked(.recordingDeviceRequired))
                    }
                    return
                }
                if persistedVersion < version || (persisted == nil && canPublish) {
                    do {
                        let saved = try await transport.advance(
                            domain: currentDomain,
                            from: persisted,
                            to: version,
                        )
                        try checkEpoch(epoch)
                        versionFloor.observe(saved.version, reason: saved.changeReason)
                        guard versionFloor.version == version else { continue }
                    } catch DataCompatibilityTransportError.conflict { continue }
                }
                try checkEpoch(epoch)
                try save(domain: currentDomain, access: .verified)
                set(.allowed(.init(domain: currentDomain, epoch: epoch)))
                return
            }
            throw DataCompatibilityTransportError.conflict
        } catch is CancellationError {
            return
        } catch {
            guard self.epoch == epoch else { return }
            if case DataCompatibilityTransportError.unavailable = error,
               let domain, let prior, prior.domain == domain, prior.access == .verified,
               prior.version == version, versionFloor.version == version
            {
                Self.logger.verificationFailed(error: .restricted(.errorDetails, error))
                set(.offline(.init(domain: domain, epoch: epoch), error))
            } else {
                if let domain = domain ?? prior?.domain {
                    do { try save(domain: domain, access: .blocked) }
                    catch {
                        Self.logger.verificationFailed(error: .restricted(.errorDetails, error))
                    }
                }
                fail(error)
            }
        }
    }

    private func save(
        domain: DataCompatibilityDomain,
        access: DataCompatibilityReceipt.Access,
    ) throws {
        try receipts.save(DataCompatibilityReceipt(
            domain: domain,
            version: versionFloor.version,
            access: access,
            removedDeviceID: removedDeviceID,
            changeReason: versionFloor.changeReason,
        ))
    }

    private func blockForUpdate() {
        set(.blocked(.updateRequired(versionFloor.version, reason: versionFloor.changeReason)))
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
        if self.state.allowsStore, !state.allowsStore { revokeAdmission() }
        self.state = state
        if case let .blocked(failure) = state {
            Self.logger.blocked(reason: .restricted(.technicalState, String(describing: failure)))
        }
        onStateChange()
    }
}
