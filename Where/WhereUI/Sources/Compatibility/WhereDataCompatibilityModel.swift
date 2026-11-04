import Observation
import WhereCore

/// Presents the dataset owner's admission state without constructing history services.
@MainActor
@Observable
public final class WhereDataCompatibilityModel {
    public enum State {
        case notChecked
        case available(DataCompatibilityCoordinator.Synchronization)
        case updateRequired(requiredMajor: UInt)
        case failed(any Error)
    }

    private enum Preparation {
        case pending
        case isolated
        case prepared(DataCompatibilityCoordinator)
        case failed(any Error)
    }

    private var preparation: Preparation
    @ObservationIgnored private let bootstrap: (any WhereScopeAssembling)?
    private var refreshTask: Task<Void, Never>?

    init(bootstrap: any WhereScopeAssembling) {
        self.bootstrap = bootstrap
        preparation = .pending
    }

    /// Already assembled preview/test services have no production dataset to verify.
    private init() {
        bootstrap = nil
        preparation = .isolated
    }

    static func isolated() -> WhereDataCompatibilityModel {
        .init()
    }

    public var state: State {
        switch preparation {
            case .pending: .notChecked
            case .isolated: .available(.verified)
            case let .failed(error): .failed(error)
            case let .prepared(coordinator):
                switch coordinator.state {
                    case .unknown: .notChecked
                    case let .available(access, synchronization):
                        access.isRevoked ? .notChecked : .available(synchronization)
                    case let .updateRequired(major): .updateRequired(requiredMajor: major)
                    case let .failed(error): .failed(error)
                }
        }
    }

    var accessID: DataCompatibilityAccess.ID? {
        guard case let .prepared(coordinator) = preparation else { return nil }
        return coordinator.access?.id
    }

    public var isChecking: Bool {
        refreshTask != nil
    }

    var blockingError: any Error {
        switch state {
            case .notChecked, .available: DataCompatibilityError.verificationRequired
            case let .updateRequired(major): DataCompatibilityError
            .updateRequired(requiredMajor: major)
            case let .failed(error): error
        }
    }

    public var isAvailable: Bool {
        if case .available = state { true } else { false }
    }

    var hasChecked: Bool {
        if case .pending = preparation { false } else { true }
    }

    /// Coalesce foreground, launch, and notification checks. A cancelled view cannot abandon
    /// verification or the withdrawal of previous-process history output.
    public func refresh() async {
        if let refreshTask { await refreshTask.value; return }
        let task = Task { await self.performRefresh() }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    func requireAdmission() async throws {
        if !isAvailable { await refresh() }
        switch state {
            case .available: return
            case .notChecked: throw DataCompatibilityError.verificationRequired
            case let .updateRequired(major):
                throw DataCompatibilityError.updateRequired(requiredMajor: major)
            case let .failed(error): throw error
        }
    }

    func importSharedEvidence(using services: WhereServices) async throws {
        guard isAvailable, services.dataAccessID == accessID else {
            throw DataCompatibilityError.verificationRequired
        }
        if let queue = try bootstrap?.sharedEvidenceDraftQueue() {
            try await services.sharedEvidence.importPending(from: queue)
        }
    }

    func withdrawHistoryOutputs() async {
        await bootstrap?.withdrawHistoryOutputs()
    }

    private func performRefresh() async {
        do {
            switch preparation {
                case .pending, .failed:
                    if let coordinator = try bootstrap?.prepareDataCompatibility() {
                        preparation = .prepared(coordinator)
                    } else {
                        preparation = .isolated
                    }
                case .isolated, .prepared: break
            }
            if case let .prepared(coordinator) = preparation {
                try await coordinator.refresh()
            }
        } catch {
            // Coordinator failures already carry their specific state, including Update Required.
            switch preparation {
                case .prepared: break
                case .pending, .isolated, .failed: preparation = .failed(error)
            }
        }
        if !isAvailable { await withdrawHistoryOutputs() }
    }
}
