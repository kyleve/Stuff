import Foundation
import Observation
import PeriscopeCore
import WhereCore

/// Keeps a guided session bound to its original review scopes. Skips affect presentation only;
/// only a successful complete reassessment can announce that the work is resolved.
@MainActor
@Observable
final class RecordingReviewFlowModel: Identifiable {
    struct ID: Hashable { let value = UUID() }
    struct Page: Identifiable {
        struct ID: Hashable { let value = UUID() }
        let id = ID()
        let itemID: RecordingReviewQueue.Item.ID
        let choice: RecordingChoiceModel
    }

    let id = ID()
    private(set) var page: Page?
    struct Progress {
        let remaining: [RecordingReviewQueue.Item]
        var skipped: Set<RecordingReviewQueue.Item.ID>

        var current: RecordingReviewQueue.Item? {
            remaining.first { !skipped.contains($0.id) }
        }
    }

    enum State {
        case idle
        indirect case refreshing(State)
        case pending(Progress)
        case failed(any Error, previous: Progress?)
        case resolved

        var progress: Progress? {
            switch self {
                case .idle, .resolved: nil
                case let .refreshing(previous): previous.progress
                case let .failed(_, previous): previous
                case let .pending(progress): progress
            }
        }

        /// Concurrent refreshes retain one stable state, including its original failure.
        var settled: State {
            if case let .refreshing(previous) = self { return previous.settled }
            return self
        }
    }

    private struct RequestID: Hashable { let value = UUID() }
    private struct ObservationID: Hashable { let value = UUID() }
    private var requestID = RequestID()
    private var observationID = ObservationID()
    private(set) var state = State.idle
    let queue: RecordingReviewQueue
    private let services: WhereServices
    private static let logger = WhereLog.session(RecordingReviewModelLog.self)

    var isRefreshing: Bool {
        if case .refreshing = state { return true }
        return false
    }

    var canReview: Bool {
        if case .pending = state { return true }
        if case let .refreshing(previous) = state,
           case .pending = previous.settled,
           page?.choice.editor != nil
        {
            // Reassessment waits for the presented editor. Keep that editor interactive so
            // the user can finish or close it; its own coordinator validates every save.
            return true
        }
        return false
    }

    init(services: WhereServices, references: [RecordingReviewReference]) throws {
        self.services = services
        queue = try RecordingReviewQueue(references: references)
    }

    /// Subscribe before the first read. A committed write drives reassessment independently
    /// of the save intent; wait for its displayed proposal to finish before changing pages.
    func observeChanges() async {
        guard !Task.isCancelled else { return }
        let observing = ObservationID()
        observationID = observing
        let changes = services.dataChangeUpdates()
        await refresh()
        for await _ in changes {
            guard !Task.isCancelled, observationID == observing else { return }
            await refresh()
        }
    }

    /// Shared by initial entry, retry, and committed store-change observation.
    func refresh() async {
        await refresh(clearingSkips: false)
    }

    private func refresh(clearingSkips: Bool) async {
        guard !Task.isCancelled else { return }
        let pending = RequestID()
        requestID = pending
        let previous = state.settled
        state = .refreshing(previous)
        do {
            let remaining = try await reassessWhenChoiceIsIdle(pending)
            guard requestID == pending else { return }
            try Task.checkCancellation()
            try services.validateDataAccess()
            if remaining.isEmpty {
                state = .resolved
            } else {
                state = .pending(Progress(
                    remaining: remaining,
                    skipped: (clearingSkips ? [] : previous.progress?.skipped ?? [])
                        .intersection(Set(remaining.map(\.id))),
                ))
            }
            reconcilePage()
        } catch is CancellationError {
            cancelPublication(pending, previous: previous)
        } catch {
            guard requestID == pending else { return }
            guard !Task.isCancelled else {
                cancelPublication(pending, previous: previous)
                return
            }
            state = .failed(error, previous: services.isDataAccessRevoked ? nil : previous.progress)
            if services.isDataAccessRevoked { clearPage() }
            Self.logger.operationFailed(error: .restricted(.errorDetails, error))
        }
    }

    func skipCurrent() {
        guard page?.choice.isBusy != true else { return }
        guard case var .pending(progress) = state else { return }
        let displayed = page.flatMap { page in
            progress.remaining.first { item in
                !progress.skipped.contains(item.id) && item.periods.contains { current in
                    page.itemID.periods.contains { $0.overlaps(current) }
                }
            }
        }
        guard let current = displayed ?? progress.current else { return }
        progress.skipped.insert(current.id)
        state = .pending(progress)
        clearPage()
        reconcilePage()
    }

    func reviewRemaining() async {
        await refresh(clearingSkips: true)
    }

    func deactivate() {
        observationID = ObservationID()
        requestID = RequestID()
        clearPage()
        state = .idle
    }

    private func reassessWhenChoiceIsIdle(_ pending: RequestID) async throws
        -> [RecordingReviewQueue.Item]
    {
        while true {
            for await busy in Observations({ self.page?.choice.isBusy ?? false }) {
                try Task.checkCancellation()
                guard requestID == pending else { throw CancellationError() }
                if !busy { break }
            }
            try Task.checkCancellation()
            guard requestID == pending else { throw CancellationError() }
            let remaining = try await services.resolution.reassess(queue)
            try Task.checkCancellation()
            guard requestID == pending else { throw CancellationError() }
            // A user action can begin while the read awaits. Do not retire its proposal from
            // an assessment obtained before that action finished; read again after it does.
            if page?.choice.isBusy != true { return remaining }
        }
    }

    private func reconcilePage() {
        guard case let .pending(progress) = state, let current = progress.current else {
            clearPage()
            return
        }
        if let page, case .failed(_, .save) = page.choice.state,
           progress.remaining.contains(where: { item in
               item.periods
                   .contains { current in page.itemID.periods.contains { $0.overlaps(current) } }
           })
        {
            // A split changes derived IDs without resolving the failed save's scope. Retain
            // its exact operation for an idempotent retry or an explicit replacement/skip.
            return
        }
        guard page?.itemID != current.id || page?.choice.didApply == true else { return }
        clearPage()
        page = Page(
            itemID: current.id,
            choice: RecordingChoiceModel(services: services, periods: current.periods),
        )
    }

    private func clearPage() {
        page?.choice.deactivate()
        page = nil
    }

    private func cancelPublication(_ pending: RequestID, previous: State) {
        guard requestID == pending else { return }
        do {
            try services.validateDataAccess()
            state = previous
        } catch {
            state = .failed(error, previous: nil)
            clearPage()
            Self.logger.operationFailed(error: .restricted(.errorDetails, error))
        }
    }
}
