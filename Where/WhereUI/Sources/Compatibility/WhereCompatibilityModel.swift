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
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var withdrawing: Task<Void, Never>?
    @ObservationIgnored private var stateRevision: UInt64 = 0
    @ObservationIgnored private var publicationID = UUID()
    @ObservationIgnored private var monitoring: Task<Void, Never>?

    init(bootstrap: any WhereScopeAssembling, initialState: DataCompatibilityState) {
        self.bootstrap = bootstrap
        state = initialState
    }

    deinit { monitoring?.cancel(); refreshTask?.cancel() }

    public var isCompatible: Bool {
        if case .compatible = state { true } else { false }
    }

    var hasControlPlane: Bool {
        coordinator != nil
    }

    func revokeAccess() async {
        await coordinator?.revokeAccess()
    }

    public func refresh() async {
        if let refreshTask { await refreshTask.value; return }
        let task = Task { [weak self] in
            guard let self else { return }
            defer { refreshTask = nil }
            if !isCompatible, case .verificationFailed = state { state = .checking }
            do {
                guard let coordinator = try await bootstrap.prepareCompatibility() else {
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
                await apply(coordinator.snapshot())
            } catch {
                await apply(.verificationFailed(error.localizedDescription))
                Self.logger(attachments: [.error(error, name: "compatibility-bootstrap-error")]) {
                    .verificationFailed(description: error.localizedDescription)
                }
            }
        }
        refreshTask = task
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
