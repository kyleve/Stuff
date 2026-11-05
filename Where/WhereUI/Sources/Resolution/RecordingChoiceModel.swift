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
        case choosing(RecordingChoiceInspection.Preview, presentation: RecordingChoicePresentation)
        case reviewed(
            RecordingChoiceInspection,
            presentation: RecordingChoicePresentation,
            refreshed: Bool,
        )

        var inspection: RecordingChoiceInspection {
            switch self {
                case let .choosing(preview, _): .ready(preview)
                case let .reviewed(inspection, _, _): inspection
            }
        }

        var presentation: RecordingChoicePresentation {
            switch self {
                case let .choosing(_, presentation), let .reviewed(_, presentation, _): presentation
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
        case awaitingControlRefresh(Content?)
        case loading(Content?)
        case ready(Content)
        case saving(Content)
        case applied(Content)
        case failed(any Error, Recovery)

        var content: Content? {
            switch self {
                case .idle: nil
                case let .loading(previous), let .awaitingControlRefresh(previous): previous
                case let .ready(content), let .saving(content), let .applied(content): content
                case let .failed(_, recovery): recovery.previous
            }
        }
    }

    private struct RequestID: Hashable { let value = UUID() }
    private var requestID = RequestID()
    private(set) var state = State.idle
    enum Editor: Identifiable {
        enum ID: Hashable {
            case calendar(RecordingCalendarEditorModel.ID)
            case places(RecordingPlaceModel.ID)
        }

        case calendar(RecordingCalendarEditorModel)
        case places(RecordingPlaceModel)
        var id: ID {
            switch self {
                case let .calendar(model): .calendar(model.id)
                case let .places(model): .places(model.id)
            }
        }

        @MainActor func deactivate() {
            switch self {
                case let .calendar(model): model.deactivate()
                case let .places(model): model.deactivate()
            }
        }
    }

    var editor: Editor? {
        didSet {
            guard oldValue?.id != editor?.id else { return }
            oldValue?.deactivate()
            if oldValue != nil, editor == nil {
                // Control edits cannot replace a failed source intent or its save identity.
                if case .failed = state { return }
                state = .awaitingControlRefresh(state.content)
            }
        }
    }

    var calendarEditor: RecordingCalendarEditorModel? {
        get { if case let .calendar(model) = editor { model } else { nil } }
        set { editor = newValue.map(Editor.calendar) }
    }

    func openPlaces() {
        guard !isBusy, !didApply, presentation != nil else { return }
        editor = .places(.init(services: services, now: services.now))
    }

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
        state.content?.presentation.names ?? [:]
    }

    var presentation: RecordingChoicePresentation? {
        state.content?.presentation
    }

    var canApply: Bool {
        guard editor == nil, case let .ready(.reviewed(inspection, _, _)) = state,
              case .ready = inspection else { return false }
        return true
    }

    var isBusy: Bool {
        if editor != nil { return true }
        return switch state {
            case .awaitingControlRefresh, .loading, .saving: true
            case .idle, .ready, .applied, .failed: false
        }
    }

    var didApply: Bool {
        if case .applied = state { return true }
        return false
    }

    var selectedAction: HistoryDecision.Action? {
        guard let content = state.content,
              case let .reviewed(_, presentation, _) = content else { return nil }
        return presentation.request.action
    }

    func loadIfNeeded() async {
        switch state {
            case .idle: await load()
            case let .awaitingControlRefresh(previous):
                if let previous, case .reviewed = previous {
                    await review(previous.presentation.request)
                } else {
                    await load()
                }
            case .loading, .ready, .saving, .applied, .failed: break
        }
    }

    func openCalendarRecovery() {
        guard !isBusy, !didApply, let presentation else { return }
        let selected: RecordingDeviceID? = switch presentation.request.scope {
            case let .recordingDay(deviceID, _): deviceID
            case .periods:
                if case let .select(deviceID) = selectedAction { deviceID } else { nil }
        }
        var devices = Set(presentation.names.keys)
        if case let .comparison(comparison) = presentation.result {
            devices.formUnion(comparison.tracks.map(\.id))
        }
        let periods: [RecordingPeriod] = switch presentation.result {
            case let .needsCalendarContext(missing): missing
            case .comparison, .absentRecordingDay:
                presentation.periods.isEmpty ? originalPeriods : presentation.periods
        }
        calendarEditor = RecordingCalendarEditorModel(
            services: services,
            periods: periods,
            devices: devices,
            names: presentation.names,
            selectedDevice: selected,
        )
    }

    func choose(_ action: HistoryDecision.Action) async {
        guard !isBusy, let presentation else { return }
        let scope: RecordingChoiceRequest.Scope = switch (presentation.request.scope, action) {
            case let (.recordingDay(_, day), .select(deviceID)):
                .recordingDay(deviceID: deviceID, day: day)
            case (.periods, .select), (_, .automatic):
                presentation.request.scope
        }
        await review(RecordingChoiceRequest(scope: scope, action: action))
    }

    func useOriginalPeriods() async {
        guard let selectedAction else { return }
        await review(.init(scope: .periods(originalPeriods), action: selectedAction))
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
            let presentation = RecordingChoicePresentation(inspection: inspection, names: names)
            try await validatePublication(pending)
            if choosing, case let .ready(preview) = inspection {
                state = .ready(.choosing(preview, presentation: presentation))
            } else {
                state = .ready(.reviewed(inspection, presentation: presentation, refreshed: false))
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
                    let presentation = RecordingChoicePresentation(
                        inspection: inspection,
                        names: names,
                    )
                    try await validatePublication(pending)
                    state = .ready(.reviewed(
                        inspection,
                        presentation: presentation,
                        refreshed: true,
                    ))
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
        editor = nil
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
