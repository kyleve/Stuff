import Foundation
import Observation
import PeriscopeCore
import RegionKit
import WhereCore

/// An explicitly supplied place and validity interval, separate from the exact reviewed save.
/// A missing coordinate or temporary-base end is incomplete input, never inferred evidence.
@MainActor
@Observable
final class RecordingPlaceEditorModel: Identifiable {
    struct ID: Hashable { let value = UUID() }
    enum DraftError: Error, Equatable { case coordinateRequired, endRequired }
    enum Intent {
        case new(at: Date)
        case definition(
            placeID: RecordingPlace.ID,
            kind: RecordingPlace.Kind,
            coordinate: Coordinate?,
            validity: RecordingInterval,
        )
        case remove(placeID: RecordingPlace.ID, validity: RecordingInterval)
    }

    @MainActor
    @Observable
    final class Bounds {
        var start: Date
        var end: Date?

        init(start: Date, end: Date?) {
            self.start = start
            self.end = end
        }

        func interval() throws -> RecordingInterval {
            try .init(start: start, end: end)
        }
    }

    @MainActor
    @Observable
    final class Definition {
        var kind: RecordingPlace.Kind
        var coordinate: Coordinate?

        init(kind: RecordingPlace.Kind, coordinate: Coordinate?) {
            self.kind = kind
            self.coordinate = coordinate
        }
    }

    enum Draft { case definition(Definition), remove }
    private struct Inspection {
        let proposal: RecordingControlEditCoordinator.Proposal
        let result: Result<RecordingPlaceInspection, any Error>
    }

    let id = ID()
    let placeID: RecordingPlace.ID
    let draft: Draft
    let bounds: Bounds
    let controls: RecordingControlModel
    private let originalValidity: RecordingInterval?
    private let services: WhereServices
    private var inspected: Inspection?
    private static let logger = WhereLog.session(RecordingReviewModelLog.self)

    init(services: WhereServices, intent: Intent) {
        self.services = services
        controls = RecordingControlModel(services: services)
        switch intent {
            case let .new(start):
                originalValidity = nil
                placeID = .init(rawValue: UUID())
                draft = .definition(.init(kind: .regularHome, coordinate: nil))
                bounds = .init(start: start, end: nil)
            case let .definition(placeID, kind, coordinate, validity):
                originalValidity = validity
                self.placeID = placeID
                draft = .definition(.init(kind: kind, coordinate: coordinate))
                bounds = .init(start: validity.start, end: validity.end)
            case let .remove(placeID, validity):
                originalValidity = nil
                self.placeID = placeID
                draft = .remove
                bounds = .init(start: validity.start, end: validity.end)
        }
    }

    var edits: Result<[RecordingControlEdit], any Error> {
        Result {
            let interval = try bounds.interval()
            let action: RecordingPlaceDecision.Action
            switch draft {
                case let .definition(definition):
                    guard let coordinate = definition.coordinate else {
                        throw DraftError.coordinateRequired
                    }
                    guard definition.kind != .temporaryBase || interval.end != nil else {
                        throw DraftError.endRequired
                    }
                    let place = try RecordingPlace(
                        id: placeID,
                        kind: definition.kind,
                        coordinate: coordinate,
                        validity: interval,
                    )
                    action = .set(kind: place.kind, coordinate: place.coordinate)
                case .remove:
                    action = .remove
            }
            var edits: [RecordingControlEdit] = [
                .place(placeID: placeID, validity: [interval], action: action),
            ]
            // Shortening a definition must end its previous tail rather than let the
            // older decision become effective again after the new boundary.
            if let originalValidity, let end = interval.end,
               originalValidity.end.map({ end < $0 }) ?? true
            {
                let tail = try RecordingInterval(
                    start: max(end, originalValidity.start),
                    end: originalValidity.end,
                )
                edits.append(.place(placeID: placeID, validity: [tail], action: .remove))
            }
            return edits
        }
    }

    var inspection: Result<RecordingPlaceInspection, any Error>? {
        guard let review = controls.state.review, let inspected,
              case let .success(edits) = edits,
              review.requestedEdits == edits,
              review.proposal == inspected.proposal else { return nil }
        return inspected.result
    }

    var canApply: Bool {
        guard case .success? = inspection else { return false }
        return controls.canApply
    }

    var canRetry: Bool {
        guard case let .failed(_, recovery) = controls.state,
              case let .success(edits) = edits else { return false }
        let requested: [RecordingControlEdit] = switch recovery {
            case let .review(requested, _): requested
            case let .save(review): review.requestedEdits
        }
        return requested == edits
    }

    func review() async {
        guard case let .success(edits) = edits else { return }
        await controls.review(edits)
        inspect()
    }

    func apply() async {
        guard canApply else { return }
        await controls.apply()
        inspect()
    }

    func retry() async {
        guard canRetry else { return }
        await controls.retry()
        inspect()
    }

    func deactivate() {
        controls.deactivate()
        inspected = nil
    }

    private func inspect() {
        guard let proposal = controls.state.review?.proposal else { inspected = nil; return }
        guard inspected?.proposal != proposal else { return }
        let result = Result { try services.recordingControlEdits.inspectPlace(proposal) }
        if case let .failure(error) = result {
            Self.logger.operationFailed(error: .restricted(.errorDetails, error))
        }
        inspected = Inspection(proposal: proposal, result: result)
    }
}
