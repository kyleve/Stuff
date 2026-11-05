import Foundation
import Observation
import PeriscopeCore
import WhereCore

/// Keeps a reviewed control batch intact through save failures. All writes use Core's
/// admitted coordinator; changed evidence requires another explicit Apply.
@MainActor
@Observable
public final class RecordingControlModel {
    struct Review {
        let proposal: RecordingControlEditCoordinator.Proposal
        let refreshed: Bool
    }

    enum Recovery {
        case review([RecordingControlEdit], previous: Review?)
        case save(Review)

        var previous: Review? {
            switch self {
                case let .review(_, previous): previous
                case let .save(review): review
            }
        }
    }

    enum State {
        case idle
        indirect case reviewing(State)
        case ready(Review)
        case saving(Review)
        case applied(Review)
        case failed(any Error, Recovery)

        var review: Review? {
            switch self {
                case .idle: nil
                case let .reviewing(previous): previous.review
                case let .ready(review), let .saving(review), let .applied(review): review
                case let .failed(_, recovery): recovery.previous
            }
        }

        var settled: State {
            if case let .reviewing(previous) = self { return previous.settled }
            return self
        }
    }

    private struct RequestID: Hashable { let value = UUID() }
    private var requestID = RequestID()
    private(set) var state = State.idle
    private let services: WhereServices
    private static let logger = WhereLog.session(RecordingReviewModelLog.self)

    #if DEBUG
        private var beforePublication: (@MainActor () async throws -> Void)?

        @_spi(Testing) public func setBeforePublicationForTesting(
            _ operation: @escaping @MainActor () async throws -> Void,
        ) {
            beforePublication = operation
        }
    #endif

    init(services: WhereServices) {
        self.services = services
    }

    var canApply: Bool {
        if case .ready = state { return true }
        return false
    }

    var isBusy: Bool {
        switch state {
            case .reviewing, .saving: true
            case .idle, .ready, .applied, .failed: false
        }
    }

    var didApply: Bool {
        if case .applied = state { return true }
        return false
    }

    func review(_ edits: [RecordingControlEdit]) async {
        guard !Task.isCancelled else { return }
        if case .saving = state { return }
        let previous = state.settled
        let pending = RequestID()
        requestID = pending
        state = .reviewing(previous)
        do {
            let proposal = try await services.recordingControlEdits.review(edits)
            try await validatePublication(pending)
            state = .ready(.init(proposal: proposal, refreshed: false))
        } catch {
            fail(
                error,
                pending: pending,
                previous: previous,
                recovery: .review(edits, previous: previous.review),
            )
        }
    }

    func apply() async {
        guard !Task.isCancelled, case let .ready(review) = state else { return }
        await save(review)
    }

    private func save(_ review: Review) async {
        let previous = state.settled
        let pending = RequestID()
        requestID = pending
        state = .saving(review)
        do {
            switch try await services.recordingControlEdits.apply(review.proposal) {
                case .applied:
                    try await validatePublication(pending)
                    state = .applied(review)
                case let .stale(proposal):
                    try await validatePublication(pending)
                    state = .ready(.init(proposal: proposal, refreshed: true))
            }
        } catch {
            fail(error, pending: pending, previous: previous, recovery: .save(review))
        }
    }

    func retry() async {
        guard !Task.isCancelled, case let .failed(_, recovery) = state else { return }
        switch recovery {
            case let .review(edits, _): await review(edits)
            case let .save(review): await save(review)
        }
    }

    func deactivate() {
        requestID = RequestID()
        state = .idle
    }

    private func validatePublication(_ pending: RequestID) async throws {
        #if DEBUG
            try await beforePublication?()
        #endif
        try Task.checkCancellation()
        guard requestID == pending else { throw CancellationError() }
        try services.validateDataAccess()
    }

    private func fail(
        _ error: any Error,
        pending: RequestID,
        previous: State,
        recovery: Recovery,
    ) {
        guard requestID == pending else { return }
        if services.isDataAccessRevoked {
            let edits: [RecordingControlEdit] = switch recovery {
                case let .review(edits, _): edits
                case let .save(review): review.proposal.edits.map(\.edit)
            }
            state = .failed(error, .review(edits, previous: nil))
        } else if error is CancellationError || Task.isCancelled {
            state = previous
            return
        } else {
            state = .failed(error, recovery)
        }
        Self.logger.operationFailed(error: .restricted(.errorDetails, error))
    }
}
