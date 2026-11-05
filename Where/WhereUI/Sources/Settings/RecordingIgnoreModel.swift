import Foundation
import Observation
import PeriscopeCore
import WhereCore

/// Owns one device's admitted ignore history and a separately retained edit. Committed changes
/// refresh the reader without replacing a displayed proposal or a failed save receipt.
@MainActor
@Observable
public final class RecordingIgnoreModel {
    enum State {
        case idle
        indirect case loading(State)
        case loaded(RecordingIgnoreHistory)
        case failed(any Error, previous: RecordingIgnoreHistory?)
        case retired

        var history: RecordingIgnoreHistory? {
            switch self {
                case .idle, .retired: nil
                case let .loading(previous): previous.history
                case let .loaded(history): history
                case let .failed(_, previous): previous
            }
        }

        var settled: State {
            if case let .loading(previous) = self { return previous.settled }
            return self
        }
    }

    private struct RequestID: Hashable { let value = UUID() }
    let deviceID: RecordingDeviceID
    let name: String
    private let services: WhereServices
    private let now: @Sendable () -> Date
    private var requestID = RequestID()
    private var observationID = RequestID()
    private(set) var state = State.idle
    private(set) var actionError: (any Error)?
    var editor: RecordingIgnoreEditorModel? {
        didSet {
            guard oldValue !== editor else { return }
            oldValue?.deactivate()
        }
    }

    private static let logger = WhereLog.session(RecordingReviewModelLog.self)

    #if DEBUG
        private var beforePublication: (@MainActor () async throws -> Void)?

        @_spi(Testing) public func setBeforePublicationForTesting(
            _ operation: @escaping @MainActor () async throws -> Void,
        ) {
            beforePublication = operation
        }
    #endif

    init(
        services: WhereServices,
        deviceID: RecordingDeviceID,
        name: String,
        now: @escaping @Sendable () -> Date,
    ) {
        self.services = services
        self.deviceID = deviceID
        self.name = name
        self.now = now
    }

    isolated deinit {
        editor?.deactivate()
    }

    var isShowingError: Bool {
        get { actionError != nil }
        set { if !newValue { actionError = nil } }
    }

    func run() async {
        guard !Task.isCancelled else { return }
        if case .retired = state { return }
        let observation = RequestID()
        observationID = observation
        let updates = services.dataChangeUpdates()
        await refresh()
        for await _ in updates {
            guard !Task.isCancelled, observationID == observation else { break }
            await refresh()
        }
    }

    func canResume(_ decision: RecordingIgnoreDecision) -> Bool {
        guard case let .ignore(until) = decision.change, until.end > now(),
              let history = state.history else { return false }
        return history.segments.contains {
            $0.period.end > now() && $0.effectiveDecisions.contains(decision.id)
                && $0.resolution != .eligible
        }
    }

    func canRestoreElapsed(_ segment: RecordingIgnoreResolver.Segment) -> Bool {
        segment.period.start < now() && segment.resolution != .eligible
    }

    func refresh() async {
        guard !Task.isCancelled else { return }
        if case .retired = state { return }
        let previous = state.settled
        let pending = RequestID()
        requestID = pending
        state = .loading(previous)
        do {
            let history = try await services.recordingControlEdits.ignoreHistory(for: deviceID)
            #if DEBUG
                try await beforePublication?()
            #endif
            try Task.checkCancellation()
            guard requestID == pending else { return }
            try services.validateDataAccess()
            state = .loaded(history)
        } catch {
            guard requestID == pending else { return }
            if services.isDataAccessRevoked {
                editor = nil
                state = .failed(error, previous: nil)
            } else if error is CancellationError || Task.isCancelled {
                state = previous
                return
            } else {
                state = .failed(error, previous: previous.history)
            }
            Self.logger.operationFailed(error: .restricted(.errorDetails, error))
        }
    }

    func start(timeZone: TimeZone) {
        open(.starting(deviceID: deviceID, at: now(), timeZone: timeZone))
    }

    func changeEnd(of decision: RecordingIgnoreDecision) {
        guard state.history?.decisions.contains(decision) == true else { return }
        open(.changingEnd(decision))
    }

    func resume(_ decision: RecordingIgnoreDecision) {
        guard state.history?.decisions.contains(decision) == true else { return }
        open(.resuming(decision, at: now()))
    }

    func restoreElapsed(_ period: RecordingPeriod) {
        guard state.history?.segments.contains(where: { $0.period == period }) == true
        else { return }
        open(.restoringElapsed(deviceID: deviceID, period: period, before: now()))
    }

    func deactivate() {
        requestID = RequestID()
        observationID = RequestID()
        state = .retired
        editor = nil
        actionError = nil
    }

    /// A retained navigation destination can disappear when another tab is selected.
    /// Stop its reads, but keep the owner and reviewed editor valid for the next appearance.
    func pause() {
        if case .retired = state { return }
        requestID = RequestID()
        observationID = RequestID()
        state = state.settled
    }

    private func open(_ intent: RecordingIgnoreEditorModel.Intent) {
        guard state.history != nil else { return }
        do {
            try services.validateDataAccess()
            editor = try .init(services: services, name: name, intent: intent)
            actionError = nil
        } catch {
            actionError = error
            if services.isDataAccessRevoked {
                editor = nil
                state = .failed(error, previous: nil)
            }
            Self.logger.operationFailed(error: .restricted(.errorDetails, error))
        }
    }
}
