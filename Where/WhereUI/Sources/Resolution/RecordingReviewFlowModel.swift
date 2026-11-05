import Foundation
import Observation
import PeriscopeCore
import WhereCore

/// Keeps a guided session bound to its original review scopes. Skips affect presentation only;
/// only a successful complete reassessment can announce that the work is resolved.
@MainActor
@Observable
final class RecordingReviewFlowModel {
    struct Progress {
        let remaining: [RecordingReviewQueue.Item]
        var skipped: Set<RecordingReviewQueue.Item.ID>

        var current: RecordingReviewQueue.Item? {
            remaining.first { !skipped.contains($0.id) }
        }
    }

    enum State {
        case idle
        case refreshing(Progress?)
        case pending(Progress)
        case failed(any Error, previous: Progress?)
        case resolved

        var progress: Progress? {
            switch self {
                case .idle, .resolved: nil
                case let .refreshing(previous), let .failed(_, previous): previous
                case let .pending(progress): progress
            }
        }
    }

    private struct RequestID: Hashable { let value = UUID() }
    private var requestID = RequestID()
    private(set) var state = State.idle
    let queue: RecordingReviewQueue
    private let services: WhereServices
    private static let logger = WhereLog.session(RecordingReviewModelLog.self)

    init(services: WhereServices, references: [RecordingReviewReference]) throws {
        self.services = services
        queue = try RecordingReviewQueue(references: references)
    }

    /// Shared by initial entry, retry, and committed store-change observation.
    func refresh() async {
        guard !Task.isCancelled else { return }
        let pending = RequestID()
        requestID = pending
        let previous = state.progress
        state = .refreshing(previous)
        do {
            let remaining = try await services.resolution.reassess(queue)
            guard requestID == pending else { return }
            try Task.checkCancellation()
            try services.validateDataAccess()
            if remaining.isEmpty {
                state = .resolved
            } else {
                state = .pending(Progress(
                    remaining: remaining,
                    skipped: (previous?.skipped ?? []).intersection(Set(remaining.map(\.id))),
                ))
            }
        } catch is CancellationError {
            cancelPublication(pending, previous: previous)
        } catch {
            guard requestID == pending else { return }
            guard !Task.isCancelled else {
                cancelPublication(pending, previous: previous)
                return
            }
            state = .failed(error, previous: services.isDataAccessRevoked ? nil : previous)
            Self.logger.operationFailed(error: .restricted(.errorDetails, error))
        }
    }

    func skipCurrent() {
        guard case var .pending(progress) = state, let current = progress.current else { return }
        progress.skipped.insert(current.id)
        state = .pending(progress)
    }

    func reviewRemaining() async {
        guard !Task.isCancelled else { return }
        do {
            try services.validateDataAccess()
            if let previous = state.progress {
                state = .pending(Progress(remaining: previous.remaining, skipped: []))
            }
            await refresh()
        } catch {
            state = .failed(error, previous: nil)
            Self.logger.operationFailed(error: .restricted(.errorDetails, error))
        }
    }

    func deactivate() {
        requestID = RequestID()
        state = .idle
    }

    private func cancelPublication(_ pending: RequestID, previous: Progress?) {
        guard requestID == pending else { return }
        do {
            try services.validateDataAccess()
            state = previous.map(State.pending) ?? .idle
        } catch {
            state = .failed(error, previous: nil)
            Self.logger.operationFailed(error: .restricted(.errorDetails, error))
        }
    }
}
