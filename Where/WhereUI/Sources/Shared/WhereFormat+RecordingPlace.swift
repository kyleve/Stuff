import Foundation
import RegionKit
import WhereCore

extension WhereFormat {
    static func recordingInterval(_ interval: RecordingInterval) -> String {
        if let end = interval.end {
            return String(localized: .recordingReviewPeriod(
                recordingInstant(interval.start),
                recordingInstant(end),
            ))
        }
        return String(localized: .recordingPlaceOngoing(recordingInstant(interval.start)))
    }

    static func recordingPlaceKind(_ kind: RecordingPlace.Kind) -> String {
        switch kind {
            case .regularHome: String(localized: .recordingPlaceHome)
            case .temporaryBase: String(localized: .recordingPlaceBase)
        }
    }

    static func recordingPlaceDefinition(_ definition: RecordingPlaceInspection
        .Definition) -> String
    {
        switch definition {
            case .absent: String(localized: .recordingPlaceAbsent)
            case let .place(kind, coordinate):
                [
                    recordingPlaceKind(kind),
                    auditCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude),
                ].formatted(.list(type: .and))
            case .conflict: String(localized: .recordingPlaceConflict)
            case .incomplete: String(localized: .recordingPlaceIncomplete)
        }
    }

    static func recordingPlaceResolution(_ resolution: RecordingPlaceResolver
        .Resolution) -> String
    {
        switch resolution {
            case .absent: recordingPlaceDefinition(.absent)
            case let .place(place): recordingPlaceDefinition(.place(
                    kind: place.kind,
                    coordinate: place.coordinate,
                ))
            case let .conflict(ids): recordingPlaceDefinition(.conflict(ids))
            case let .incomplete(ids): recordingPlaceDefinition(.incomplete(ids))
        }
    }

    static func recordingPlaceActionLabel(
        _ action: String,
        segment: RecordingPlaceResolver.Segment,
    ) -> String {
        String(localized: .recordingPlaceActionContext(
            action,
            recordingPlaceResolution(segment.resolution),
            recordingInterval(segment.period),
        ))
    }

    static func recordingPlaceAction(_ action: RecordingPlaceDecision.Action) -> String {
        switch action {
            case let .set(kind, coordinate): recordingPlaceDefinition(.place(
                    kind: kind,
                    coordinate: coordinate,
                ))
            case .remove: recordingPlaceDefinition(.absent)
        }
    }

    static func recordingControlScope(_ scope: VersionedHistoryRecord.Scope) -> String {
        switch scope {
            case .entireHistory: String(localized: .recordingPlaceEntireHistory)
            case let .periods(periods): periods.map(recordingPeriod).formatted(.list(type: .and))
            case let .intervals(intervals): intervals.map(recordingInterval)
            .formatted(.list(type: .and))
        }
    }

    @MainActor static func recordingPlaceFailure(_ error: any Error) -> String {
        if let error = error as? RecordingPlaceEditorModel.DraftError {
            switch error {
                case .coordinateRequired: return String(
                        localized: .recordingPlaceCoordinateRequired,
                    )
                case .endRequired: return String(localized: .recordingPlaceEndRequired)
            }
        }
        if let error = error as? RecordingPlace.ValidationError {
            switch error {
                case .invalidCoordinate: return String(localized: .recordingPlaceCoordinateInvalid)
                case .temporaryBaseRequiresEnd: return String(localized: .recordingPlaceEndRequired)
            }
        }
        if error is RecordingInterval
            .ValidationError { return String(localized: .recordingPlaceIntervalInvalid) }
        if error is DataCompatibilityAccess
            .AccessError { return String(localized: .recordingPlaceUnavailable) }
        return String(localized: .recordingPlaceFailed)
    }
}
