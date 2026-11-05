import Foundation
import Observation
import PeriscopeCore
import WhereCore

/// Owns admitted place history and a separately retained edit. Committed changes
/// refresh the reader without replacing a displayed proposal or a failed save receipt.
@MainActor
@Observable
public final class RecordingPlaceModel {
    struct ID: Hashable { let value = UUID() }
    let id = ID()
    enum State {
        case idle
        indirect case loading(State)
        case loaded(RecordingPlaceHistory)
        case failed(any Error, previous: RecordingPlaceHistory?)
        case retired

        var history: RecordingPlaceHistory? {
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
    private let services: WhereServices
    private let now: @Sendable () -> Date
    private var requestID = RequestID()
    private var observationID = RequestID()
    private(set) var state = State.idle
    private(set) var actionError: (any Error)?
    var editor: RecordingPlaceEditorModel? {
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
        now: @escaping @Sendable () -> Date,
    ) {
        self.services = services
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

    func refresh() async {
        guard !Task.isCancelled else { return }
        if case .retired = state { return }
        let previous = state.settled
        let pending = RequestID()
        requestID = pending
        state = .loading(previous)
        do {
            let history = try await services.recordingControlEdits.placeHistory()
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

    func start() {
        open(.new(at: now()))
    }

    /// Resolved segments supply a definition; unresolved ones require explicit user input.
    /// Never select one conflicting saved decision by its position in the history list.
    func edit(placeID: RecordingPlace.ID, segment: RecordingPlaceResolver.Segment) {
        guard state.history?.entries.contains(where: {
            $0.placeID == placeID && $0.segments.contains(segment)
        }) == true else { return }
        switch segment.resolution {
            case let .place(place):
                open(.definition(
                    placeID: placeID,
                    kind: place.kind,
                    coordinate: place.coordinate,
                    validity: segment.period,
                ))
            case .absent, .conflict, .incomplete:
                open(.definition(
                    placeID: placeID,
                    kind: .regularHome,
                    coordinate: nil,
                    validity: segment.period,
                ))
        }
    }

    enum CurrentAction { case change, end }

    func isCurrent(_ segment: RecordingPlaceResolver.Segment) -> Bool {
        guard case .place = segment.resolution else { return false }
        return segment.period.contains(now())
    }

    /// Capture one current instant for the intent. Later definitions remain outside this scope.
    func current(
        _ action: CurrentAction,
        placeID: RecordingPlace.ID,
        segment: RecordingPlaceResolver.Segment,
    ) {
        let instant = now()
        guard state.history?.entries.contains(where: {
            $0.placeID == placeID && $0.segments.contains(segment)
        }) == true, segment.period.contains(instant),
            case let .place(place) = segment.resolution else { return }
        do {
            let validity = try RecordingInterval(start: instant, end: segment.period.end)
            switch action {
                case .change:
                    open(.definition(
                        placeID: placeID,
                        kind: place.kind,
                        coordinate: place.coordinate,
                        validity: validity,
                    ))
                case .end:
                    open(.remove(placeID: placeID, validity: validity))
            }
        } catch { failAction(error) }
    }

    /// Removal has an explicit scope. Editing the start can end a home without rewriting its past.
    func remove(placeID: RecordingPlace.ID, segment: RecordingPlaceResolver.Segment) {
        guard state.history?.entries.contains(where: {
            $0.placeID == placeID && $0.segments.contains(segment)
        }) == true else { return }
        open(.remove(placeID: placeID, validity: segment.period))
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

    private func open(_ intent: RecordingPlaceEditorModel.Intent) {
        guard state.history != nil else { return }
        do {
            try services.validateDataAccess()
            editor = .init(services: services, intent: intent)
            actionError = nil
        } catch { failAction(error) }
    }

    private func failAction(_ error: any Error) {
        actionError = error
        if services.isDataAccessRevoked {
            editor = nil
            state = .failed(error, previous: nil)
        }
        Self.logger.operationFailed(error: .restricted(.errorDetails, error))
    }
}
