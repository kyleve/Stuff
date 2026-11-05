import Foundation
import Observation
import PeriscopeCore
import WhereCore

/// Presents one exact source proposal. Merely opening a review never selects an action;
/// changed evidence replaces the preview and requires another explicit Apply.
@MainActor
@Observable
public final class RecordingChoiceModel {
    enum Content {
        case choosing(RecordingChoiceInspection.Preview, names: [RecordingDeviceID: String])
        case reviewed(
            RecordingChoiceInspection,
            names: [RecordingDeviceID: String],
            refreshed: Bool,
        )

        var inspection: RecordingChoiceInspection {
            switch self {
                case let .choosing(preview, _): .ready(preview)
                case let .reviewed(inspection, _, _): inspection
            }
        }

        var names: [RecordingDeviceID: String] {
            switch self {
                case let .choosing(_, names), let .reviewed(_, names, _): names
            }
        }
    }

    enum Recovery {
        case load
        case review(RecordingChoiceRequest, previous: Content?)
        case save(Content)

        var previous: Content? {
            switch self {
                case .load: nil
                case let .review(_, previous): previous
                case let .save(content): content
            }
        }
    }

    enum State {
        case idle
        case loading(Content?)
        case ready(Content)
        case saving(Content)
        case applied(Content)
        case failed(any Error, Recovery)

        var content: Content? {
            switch self {
                case .idle: nil
                case let .loading(previous): previous
                case let .ready(content), let .saving(content), let .applied(content): content
                case let .failed(_, recovery): recovery.previous
            }
        }
    }

    private struct RequestID: Hashable { let value = UUID() }
    private var requestID = RequestID()
    private(set) var state = State.idle
    let originalPeriods: [RecordingPeriod]
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

    public init(services: WhereServices, periods: [RecordingPeriod]) {
        self.services = services
        originalPeriods = periods
    }

    var inspection: RecordingChoiceInspection? {
        state.content?.inspection
    }

    var deviceNames: [RecordingDeviceID: String] {
        state.content?.names ?? [:]
    }

    var canApply: Bool {
        guard case let .ready(.reviewed(inspection, _, _)) = state,
              case .ready = inspection else { return false }
        return true
    }

    var isBusy: Bool {
        switch state {
            case .loading, .saving: true
            case .idle, .ready, .applied, .failed: false
        }
    }

    var didApply: Bool {
        if case .applied = state { return true }
        return false
    }

    func load() async {
        await inspect(
            .init(scope: .periods(originalPeriods), action: .automatic),
            choosing: true,
        )
    }

    func review(_ request: RecordingChoiceRequest) async {
        await inspect(request, choosing: false)
    }

    private func inspect(_ request: RecordingChoiceRequest, choosing: Bool) async {
        guard !Task.isCancelled else { return }
        if case .saving = state { return }
        let previous = state.content
        let recovery: Recovery = choosing ? .load : .review(request, previous: previous)
        let pending = RequestID()
        requestID = pending
        state = .loading(previous)
        do {
            let inspection = try await services.recordingChoices.inspect(request)
            let names = try await services.recording.displayNames()
            try await validatePublication(pending)
            if choosing, case let .ready(preview) = inspection {
                state = .ready(.choosing(preview, names: names))
            } else {
                state = .ready(.reviewed(inspection, names: names, refreshed: false))
            }
        } catch is CancellationError {
            if requestID == pending { state = .idle }
        } catch {
            fail(error, pending: pending, recovery: recovery)
        }
    }

    func apply() async {
        guard !Task.isCancelled, canApply, let content = state.content,
              case let .ready(preview) = content.inspection else { return }
        let pending = RequestID()
        requestID = pending
        state = .saving(content)
        do {
            let result = try await services.recordingChoices.apply(preview.proposal)
            switch result {
                case .applied:
                    try await validatePublication(pending)
                    state = .applied(content)
                case let .stale(review):
                    let inspection = try await services.recordingChoices.inspection(of: review)
                    let names = try await services.recording.displayNames()
                    try await validatePublication(pending)
                    state = .ready(.reviewed(inspection, names: names, refreshed: true))
            }
        } catch is CancellationError {
            // A commit can finish after the screen closes. The next entry reads current history;
            // cancellation must not announce a save or advance the guided queue.
            if requestID == pending { state = .idle }
        } catch {
            fail(error, pending: pending, recovery: .save(content))
        }
    }

    func retry() async {
        guard !Task.isCancelled, case let .failed(_, recovery) = state else { return }
        switch recovery {
            case .load: await load()
            case let .review(request, _): await review(request)
            case let .save(content):
                do {
                    try services.validateDataAccess()
                    state = .ready(content)
                    await apply()
                } catch {
                    fail(error, pending: requestID, recovery: .load)
                }
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

    private func fail(_ error: any Error, pending: RequestID, recovery: Recovery) {
        guard requestID == pending else { return }
        guard !Task.isCancelled else {
            state = .idle
            return
        }
        state = .failed(error, services.isDataAccessRevoked ? .load : recovery)
        Self.logger.operationFailed(error: .restricted(.errorDetails, error))
    }
}
