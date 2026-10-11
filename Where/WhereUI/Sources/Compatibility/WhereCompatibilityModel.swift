import Observation
import WhereCore

/// Process-owned verification and history observation; it never owns normal app services.
@MainActor
@Observable
public final class WhereCompatibilityModel {
    public private(set) var state: DataCompatibilityState
    @ObservationIgnored private var coordinator: DataCompatibilityCoordinator?
    private let bootstrap: any WhereScopeAssembling
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
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
            if !isCompatible { state = .checking }
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
                            // A history event that lands during verification needs a fresh read
                            // after that pass; joining the older result could miss the new floor.
                            if let pending = self?.refreshTask { await pending.value }
                            await self?.refresh()
                        }
                    }
                }
                state = await coordinator.recheck()
            } catch {
                state = .verificationFailed(error.localizedDescription)
                Self.logger(attachments: [.error(error, name: "compatibility-bootstrap-error")]) {
                    .verificationFailed(description: error.localizedDescription)
                }
            }
        }
        refreshTask = task
        await task.value
    }

    private static let logger = WhereLog.root(WhereCompatibilityLog.self)
}
