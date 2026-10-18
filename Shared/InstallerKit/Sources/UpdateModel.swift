import Foundation
import Observation

/// One process-owned presentation mirror; the service owns feed and cache policy.
@MainActor
@Observable
public final class UpdateModel {
    public enum State {
        case idle
        case checking(previous: UpdateService.Snapshot?)
        case loaded(UpdateService.Snapshot)
        case failed(any Error, previous: UpdateService.Snapshot?)

        public var snapshot: UpdateService.Snapshot? {
            switch self {
                case .idle: nil
                case let .checking(previous), let .failed(_, previous): previous
                case let .loaded(snapshot): snapshot
            }
        }
    }

    public let installed: InstalledBuild
    private let service: UpdateService
    private var refreshSequence: UInt64 = 0
    public private(set) var state: State

    public init(service: UpdateService) {
        self.service = service
        installed = service.installed
        state = service.cached.map(State.loaded) ?? .idle
    }

    public var needsAttention: Bool {
        state.snapshot?.availability.needsAttention == true
    }

    public var isChecking: Bool {
        if case .checking = state { return true }
        return false
    }

    public func refresh(force: Bool) async {
        guard !Task.isCancelled else { return }
        // A cache-only foreground check must leave the active check's presentation intact.
        if !force, isChecking, service.cachedForAutomaticRefresh != nil { return }
        refreshSequence += 1
        let sequence = refreshSequence
        let previousState = isChecking ? state.snapshot.map(State.loaded) ?? .idle : state
        state = .checking(previous: state.snapshot)
        do {
            let snapshot = try await service.refresh(force: force)
            try Task.checkCancellation()
            guard sequence == refreshSequence else { return }
            state = .loaded(snapshot)
        } catch is CancellationError {
            guard sequence == refreshSequence else { return }
            state = previousState
        } catch {
            guard sequence == refreshSequence else { return }
            // Core logs the original error. Keep it here with the last successful result.
            state = .failed(error, previous: previousState.snapshot)
        }
    }
}
