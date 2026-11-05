import Foundation
import RegionKit

/// Compares precise place definitions in the exact reviewed proposal. This is supporting
/// place evidence, not a preview of selected observations or report totals.
public struct RecordingPlaceInspection: Hashable, Sendable {
    public enum Definition: Hashable, Sendable {
        case absent
        case place(kind: RecordingPlace.Kind, coordinate: Coordinate)
        case conflict(Set<RecordingPlaceDecision.ID>)
        case incomplete(Set<RecordingPlaceDecision.ID>)

        init(_ resolution: RecordingPlaceResolver.Resolution) {
            self = switch resolution {
                case .absent: .absent
                case let .place(place): .place(kind: place.kind, coordinate: place.coordinate)
                case let .conflict(identities): .conflict(identities)
                case let .incomplete(identities): .incomplete(identities)
            }
        }
    }

    public struct Change: Hashable, Sendable {
        public let period: RecordingPeriod
        public let before: Definition
        public let after: Definition
    }

    public enum ValidationError: Error, Equatable { case notAPlace, multiplePlaces }

    public let placeID: RecordingPlace.ID
    public let changes: [Change]
    /// A place edit does not resolve opaque controls. Preserve their exact scopes in the UI.
    public let unknownControls: [VersionedHistoryRecord]

    init(
        proposal: RecordingControlEditCoordinator.Proposal,
        policy: DataCompatibilityPolicy,
    ) throws {
        let places = proposal.edits.compactMap { prepared -> RecordingPlaceDecision? in
            if case let .place(decision) = prepared.control { return decision }
            return nil
        }
        guard let first = places.first, places.count == proposal.edits.count
        else { throw ValidationError.notAPlace }
        guard places.allSatisfy({ $0.placeID == first.placeID })
        else { throw ValidationError.multiplePlaces }
        placeID = first.placeID
        let evidence = proposal.evidence
        let records = try proposal.edits.map {
            try RecordingControlCodec.encode($0.control, generationID: evidence.generationID)
        }
        let after = try RecordingControlSnapshot(
            records: evidence.controls.records + records,
            generationID: evidence.generationID,
            policy: policy,
        )
        var changes: [Change] = []
        for period in evidence.query.periods {
            let beforeSegments = try RecordingPlaceResolver.resolve(
                evidence.controls.places,
                for: first.placeID,
                within: period,
                version: evidence.policyVersion,
            )
            let afterSegments = try RecordingPlaceResolver.resolve(
                after.places,
                for: first.placeID,
                within: period,
                version: evidence.policyVersion,
            )
            let boundaries = Set((beforeSegments + afterSegments).flatMap {
                [$0.period.start, $0.period.end]
            }).sorted()
            for (start, end) in zip(boundaries, boundaries.dropFirst()) {
                guard let before = beforeSegments.first(where: { $0.period.contains(start) }),
                      let after = afterSegments.first(where: { $0.period.contains(start) })
                else { preconditionFailure("Place resolution must cover the reviewed period.") }
                try changes.append(Change(
                    period: .init(start: start, end: end),
                    before: Definition(before.resolution),
                    after: Definition(after.resolution),
                ))
            }
        }
        self.changes = changes
        unknownControls = evidence.controls.requiresReview
    }
}
