import Foundation
@testable import WhereCore

@MainActor
final class RecordingCoordinationInstallation: InstallationRecordingContextStoring {
    var onboardingContext: InstallationRecordingContext
    var backupImportRecovery: BackupCoordinator.DurableImportRecovery?
    var onboardingImportCompletion: BackupCoordinator.OnboardingImportCompletion?
    var failsControlWrite = false
    struct WriteFailure: Error {}

    init(deviceID: RecordingDeviceID) {
        onboardingContext = .init(
            currentDevice: .init(id: deviceID, systemName: "Test phone", kind: .phone),
            registeredAt: Date(),
            recordingChoice: .unconfirmed,
            isRejoining: false,
        )
    }

    func resolve() throws -> InstallationRecordingContext {
        onboardingContext
    }

    func confirmInitialRecording(isEnabled: Bool) throws -> InstallationRecordingContext {
        if onboardingContext.automaticRecordingEnabled == nil {
            onboardingContext = onboardingContext.confirmingInitialRecording(isEnabled: isEnabled)
        }
        return onboardingContext
    }

    func setAutomaticRecordingEnabled(_ isEnabled: Bool) throws {
        onboardingContext = onboardingContext.settingAutomaticRecordingEnabled(
            isEnabled,
            at: Date(),
        )
    }

    func setRecordingControl(_ control: RecordingInstallationControl) throws {
        if failsControlWrite { throw WriteFailure() }
        onboardingContext = onboardingContext.settingRecordingControl(control)
    }

    func rejoin() throws -> InstallationRecordingContext {
        onboardingContext = .init(
            currentDevice: .init(
                id: .init(rawValue: UUID()),
                systemName: "Test phone",
                kind: .phone,
            ),
            registeredAt: Date(),
            recordingChoice: .unconfirmed,
            isRejoining: true,
        )
        return onboardingContext
    }

    func setBackupImportRecovery(_ recovery: BackupCoordinator.DurableImportRecovery?) {
        backupImportRecovery = recovery
    }

    func recordOnboardingImportCompletion(_ completion: BackupCoordinator
        .OnboardingImportCompletion)
    {
        onboardingImportCompletion = completion
    }

    func reset() throws {
        _ = try rejoin()
    }
}

/// Holds a network boundary until the test applies its competing transition.
actor RecordingCoordinationGate {
    private enum State {
        case idle([CheckedContinuation<Void, Never>])
        case held(CheckedContinuation<Void, Never>)
        case resumed
    }

    private var state: State = .idle([])

    func suspend() async {
        await withCheckedContinuation { continuation in
            guard case let .idle(waiters) = state else { preconditionFailure("Gate reused") }
            state = .held(continuation)
            for waiter in waiters {
                waiter.resume()
            }
        }
    }

    func waitUntilEntered() async {
        guard case .idle = state else { return }
        await withCheckedContinuation { continuation in
            guard case let .idle(waiters) = state else { preconditionFailure("Gate changed") }
            state = .idle(waiters + [continuation])
        }
    }

    func resume() {
        guard case let .held(continuation) = state else { return }
        state = .resumed
        continuation.resume()
    }
}

/// Reproduces uncertain server outcomes without touching CloudKit.
actor RecordingCoordinationTransport: RecordingAuthorityTransport {
    enum Response { case normal, lostAfterCommit, delayedCommit }
    struct LostResponse: Error {}
    private let server = LocalRecordingAuthorityTransport(now: { Date() })
    private var response: Response = .normal
    private var delayed: RecordingAuthorityProposal?
    private var cancelGate: RecordingCoordinationGate?

    func setResponse(_ response: Response) {
        self.response = response
    }

    func holdCancellation(_ gate: RecordingCoordinationGate) {
        cancelGate = gate
    }

    func current() async -> RecordingAuthorityCommit? {
        await server.current()
    }

    func fetchCommit(for eventID: RecordingAuthority.EventID) async -> RecordingAuthorityCommit? {
        await server.fetchCommit(for: eventID)
    }

    func commit(_ proposal: RecordingAuthorityProposal) async throws -> RecordingAuthorityCommit {
        if proposal.kind == .cancel, let gate = cancelGate {
            cancelGate = nil
            await gate.suspend()
        }
        let response = response
        self.response = .normal
        switch response {
            case .normal: return try await server.commit(proposal)
            case .lostAfterCommit:
                _ = try await server.commit(proposal)
                throw LostResponse()
            case .delayedCommit:
                delayed = proposal
                throw LostResponse()
        }
    }

    func commitDelayedProposal() async throws {
        guard let delayed else { preconditionFailure("No delayed proposal") }
        _ = try await server.commit(delayed)
        self.delayed = nil
    }
}
