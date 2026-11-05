import Foundation
import RegionKit
import WhereCore

/// Prepared rendering values for one immutable inspection. Maps separate devices and physical
/// coverage pieces; thinning their geometry never changes the proposal or its raw observations.
struct RecordingChoicePresentation {
    struct Track: Identifiable {
        let id: RecordingDeviceID
        let name: String
        let map: RecordedMapData
        let observations: [RecordingObservation]
        let gaps: [RecordingPeriod]
        let days: RecordingHistorySelection.Days
    }

    struct Explanation: Identifiable {
        let period: RecordingPeriod
        let text: String
        var id: RecordingPeriod {
            period
        }
    }

    struct RemainingIssue: Identifiable {
        let id: RecordingIssue.ID
        let period: RecordingPeriod
        let days: RecordingHistorySelection.Days
        let explanation: String

        init(issue: RecordingIssue, names: [RecordingDeviceID: String]) {
            id = issue.id
            period = issue.period
            days = issue.days
            explanation = Set(issue.segments.map {
                WhereFormat.recordingSelection(.unresolved($0.problem), names: names)
            }).sorted().joined(separator: "\n")
        }
    }

    struct Comparison {
        let tracks: [Track]
        let before: [DayPresence]
        let after: [DayPresence]
        let explanations: [Explanation]
        let remainingIssues: [RemainingIssue]
    }

    enum Result {
        case comparison(Comparison)
        case needsCalendarContext([RecordingPeriod])
        case absentRecordingDay
    }

    let request: RecordingChoiceRequest
    let periods: [RecordingPeriod]
    let names: [RecordingDeviceID: String]
    let result: Result

    init(inspection: RecordingChoiceInspection, names: [RecordingDeviceID: String]) {
        self.names = names
        switch inspection {
            case let .ready(preview):
                request = preview.proposal.request
                periods = preview.proposal.decision.periods
                result = .comparison(Comparison(
                    tracks: preview.tracks.map { Self.track($0, names: names) },
                    before: preview.before.contributions,
                    after: preview.after.contributions,
                    explanations: preview.before.selections.flatMap(\.segments).map {
                        Explanation(period: $0.period, text: WhereFormat.recordingSelection(
                            $0.resolution,
                            names: names,
                        ))
                    },
                    remainingIssues: preview.after.issues.map { RemainingIssue(
                        issue: $0,
                        names: names,
                    ) },
                ))
            case let .needsCalendarContext(clarification):
                request = clarification.request
                periods = []
                result = .needsCalendarContext(clarification.missingPeriods)
            case let .absentRecordingDay(request):
                self.request = request
                periods = []
                result = .absentRecordingDay
        }
    }

    private static func track(
        _ track: RecordingChoiceInspection.Track,
        names: [RecordingDeviceID: String],
    ) -> Track {
        let observations = track.observations.sorted {
            if $0.sample.timestamp != $1.sample
                .timestamp { return $0.sample.timestamp < $1.sample.timestamp }
            return $0.sample.id.uuidString < $1.sample.id.uuidString
        }
        let points = observations.flatMap { observation in
            var attributions = Region.inCanonicalOrder(observation.geography.knownRegions)
                .map(RecordedMapPoint.Attribution.region)
            if observation.geography.includesUnknownPresence { attributions.append(.unknown) }
            if attributions.isEmpty { attributions.append(.excluded) }
            return attributions.map { RecordedMapPoint(
                coordinate: observation.sample.coordinate,
                horizontalAccuracy: observation.sample.horizontalAccuracy,
                attribution: $0,
            ) }
        }
        let routes = track.availablePeriods.map { period in
            RecordedMapData.Route(
                id: .coverage(deviceID: track.deviceID, period: period),
                coordinates: observations.filter { period.contains($0.sample.timestamp) }
                    .map(\.sample.coordinate),
            )
        }
        var known: Set<CalendarDay> = []
        var unknown = false
        for observation in observations {
            switch observation.recordingDay {
                case let .resolved(context): known.insert(context.day)
                case .unresolved: unknown = true
            }
        }
        return Track(
            id: track.deviceID,
            name: WhereFormat.recordingDevice(track.deviceID, names: names),
            map: RecordedMapData(points: points, routes: routes),
            observations: observations,
            gaps: track.gaps,
            days: unknown ? .unassigned(known: known) : .known(known),
        )
    }
}
