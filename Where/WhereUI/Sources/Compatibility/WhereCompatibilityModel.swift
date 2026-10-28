import Foundation
import Observation
import WhereCore

/// Process-owned verification and history observation; it never owns normal app services.
@MainActor
@Observable
public final class WhereCompatibilityModel {
    public var onStateChange: (@MainActor (DataCompatibilityState) async -> Void)?
    public private(set) var state: DataCompatibilityState
    @ObservationIgnored private var coordinator: DataCompatibilityCoordinator?
    private let bootstrap: any WhereScopeAssembling
    private struct Refresh {
        struct ID: Equatable { let rawValue = UUID() }
        let id: ID
        let task: Task<Void, Never>
    }

    private struct InvalidationID: Equatable { let rawValue = UUID() }
    @ObservationIgnored private var refreshOperation: Refresh?
    @ObservationIgnored private var withdrawing: Task<Void, Never>?
    @ObservationIgnored private var stateRevision: UInt64 = 0
    @ObservationIgnored private var publicationID = UUID()
    @ObservationIgnored private var monitoring: Task<Void, Never>?

    init(bootstrap: any WhereScopeAssembling, initialState: DataCompatibilityState) {
        self.bootstrap = bootstrap
        state = initialState
    }

    deinit { monitoring?.cancel(); refreshOperation?.task.cancel() }

    public var isCompatible: Bool {
        if case .compatible = state { true } else { false }
    }

    var hasControlPlane: Bool {
        coordinator != nil
    }

    func revokeAccess() async {
        await coordinator?.revokeAccess()
    }

    @ObservationIgnored private var invalidationID: InvalidationID?

    public func invalidateAccount() async {
        let invalidationID = InvalidationID()
        self.invalidationID = invalidationID
        defer { if self.invalidationID == invalidationID { self.invalidationID = nil } }
        refreshOperation?.task.cancel()
        refreshOperation = nil
        // Publish a blocking state so the lifecycle drains the old world during verification.
        state = .verificationFailed(RecordingAccountError.verificationRequired.localizedDescription)
        do {
            let coordinator = try await bootstrap.prepareCompatibility()
            self.coordinator = coordinator
            await coordinator?.invalidateAccount()
            if let coordinator { await apply(coordinator.snapshot()) }
            else { await apply(state) }
        } catch {
            await apply(.verificationFailed(error.localizedDescription))
            Self.logger.verificationFailed(error: .restricted(.errorDetails, error))
        }
    }

    public func refresh() async {
        guard invalidationID == nil else { return }
        if let refreshOperation { await refreshOperation.task.value; return }
        let refreshID = Refresh.ID()
        let task = Task { [weak self] in
            guard let self else { return }
            defer { if self.refreshOperation?.id == refreshID { refreshOperation = nil } }
            do {
                let prepared = try await bootstrap.prepareCompatibility()
                guard refreshOperation?.id == refreshID else { return }
                guard let coordinator = prepared else {
                    state = .compatible(.current)
                    return
                }
                self.coordinator = coordinator
                if monitoring == nil {
                    let changes = coordinator.changes()
                    monitoring = Task { [weak self] in
                        for await _ in changes {
                            guard !Task.isCancelled else { return }
                            // Inspect local requirements even while remote verification is
                            // suspended.
                            _ = await coordinator.recheckLocalHistory()
                            await self?.apply(coordinator.snapshot())
                        }
                    }
                }
                _ = await coordinator.recheck()
                guard refreshOperation?.id == refreshID else { return }
                await apply(coordinator.snapshot())
            } catch {
                guard refreshOperation?.id == refreshID else { return }
                await apply(.verificationFailed(error.localizedDescription))
                Self.logger.verificationFailed(error: .restricted(.errorDetails, error))
            }
        }
        refreshOperation = Refresh(id: refreshID, task: task)
        await task.value
    }

    private func apply(_ snapshot: DataCompatibilitySnapshot) async {
        guard snapshot.revision >= stateRevision else { return }
        stateRevision = snapshot.revision
        await apply(snapshot.state)
    }

    private func apply(_ newState: DataCompatibilityState) async {
        let publicationID = UUID()
        self.publicationID = publicationID
        if case .compatible = newState { await withdrawing?.value }
        guard self.publicationID == publicationID else { return }
        let targetState: DataCompatibilityState = if case .updateRequired = state { state }
        else { newState }
        if case .compatible = targetState {
            // Unblock the process handoff before observation can resume launch and
            // install the replacement services.
            await onStateChange?(targetState)
            guard self.publicationID == publicationID else { return }
            state = targetState
            return
        }
        state = targetState
        if !isCompatible {
            if withdrawing == nil {
                withdrawing = Task {
                    await bootstrap.withdrawCompatibilityOutputs()
                    withdrawing = nil
                }
            }
            await withdrawing?.value
        }
        guard self.publicationID == publicationID else { return }
        await onStateChange?(state)
    }

    private static let logger = WhereLog.root(WhereCompatibilityLog.self)
}
