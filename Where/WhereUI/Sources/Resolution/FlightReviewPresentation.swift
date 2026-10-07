import Foundation
import RegionKit
import WhereCore

/// Builds map geometry and edit lookups once for each accepted review value.
struct FlightReviewPresentation {
    struct Point: Identifiable {
        enum Evidence: Equatable {
            case inferred(FlightEndpointInference.Reason)
            case airborne
            case ground
            case uncertain

            var explanation: String {
                switch self {
                    case .inferred(.recordingGap): String(localized: .flightReviewPointGap)
                    case .inferred(.recordedSpeed): String(localized: .flightReviewPointSpeed)
                    case .airborne: String(localized: .flightReviewPointAirborne)
                    case .ground: String(localized: .flightReviewPointGround)
                    case .uncertain: String(localized: .flightReviewPointUncertain)
                }
            }
        }

        var id: LocationSample.ID {
            point.sample.id
        }

        let point: SampleCorrectionPoint
        let evidence: Evidence
        let correction: FlightPointCorrection?
        let map: RecordedMapData

        init(point: SampleCorrectionPoint, evidence: Evidence, correction: FlightPointCorrection?) {
            self.point = point
            self.evidence = evidence
            self.correction = correction
            map = RecordedMapData(
                points: FlightReviewPresentation.mapPoints(for: point),
                routes: [],
            )
        }
    }

    let review: GPSCorrectionReview
    let map: RecordedMapData
    let editedPoints: [SampleCorrectionPoint]
    let replacements: [LocationSample.ID: Set<Region>]
    let recordedPoints: [Point]
    let inferredEndpoints: [LocationSample.ID: FlightEndpointInference.Reason]

    init(review: GPSCorrectionReview) {
        self.review = review
        let points = review.points.sorted {
            if $0.sample.timestamp != $1.sample
                .timestamp { return $0.sample.timestamp < $1.sample.timestamp }
            return $0.sample.id.uuidString < $1.sample.id.uuidString
        }
        let mapPoints = points.flatMap(Self.mapPoints)
        var tracks: [FlightAssessment.RecordingSource: [Coordinate]] = [:]
        var trackOrder: [FlightAssessment.RecordingSource] = []
        for point in points where point.sample.source.isGPS {
            let source = point.sample.recordingDeviceID
                .map(FlightAssessment.RecordingSource.device) ?? .legacy
            if tracks[source] == nil { trackOrder.append(source) }
            tracks[source, default: []].append(point.sample.coordinate)
        }
        map = RecordedMapData(points: mapPoints, routes: trackOrder.map {
            RecordedMapData.Route(id: $0, coordinates: tracks[$0] ?? [])
        })
        let edits = review.proposal?.edits ?? []
        replacements = Dictionary(
            edits.map { ($0.sampleID, $0.replacementRegions) },
            uniquingKeysWith: { first, _ in first },
        )
        var remaining = Set(edits.map(\.sampleID))
        editedPoints = points.filter { remaining.remove($0.sample.id) != nil }
        let inferred = Dictionary(
            review.flights.flatMap(\.inferredEndpoints).map { ($0.sampleID, $0.reason) },
            uniquingKeysWith: { first, _ in first },
        )
        inferredEndpoints = inferred
        let airborne = review.flights
            .reduce(into: Set<LocationSample.ID>()) { $0.formUnion($1.airborneSampleIDs) }
        let ground = review.flights
            .reduce(into: Set<LocationSample.ID>()) { $0.formUnion($1.groundSampleIDs) }
        let corrections = Dictionary(
            review.pointCorrections.map { ($0.sampleID, $0) },
            uniquingKeysWith: { first, _ in first },
        )
        var seen: Set<LocationSample.ID> = []
        recordedPoints = points
            .filter { $0.sample.source.isGPS && seen.insert($0.sample.id).inserted }
            .map { point in
                let evidence: Point.Evidence = if let reason = inferred[point.sample.id] {
                    .inferred(reason)
                } else if ground.contains(point.sample.id) {
                    .ground
                } else if airborne.contains(point.sample.id) {
                    .airborne
                } else {
                    .uncertain
                }
                return Point(
                    point: point,
                    evidence: evidence,
                    correction: corrections[point.sample.id],
                )
            }
    }

    private static func mapPoints(for point: SampleCorrectionPoint) -> [RecordedMapPoint] {
        // Excluded airborne fixes remain visible as raw observations on every review map.
        let attributions: [RecordedMapPoint.Attribution] = point.regions.isEmpty
            ? [.excluded] : Region.inCanonicalOrder(point.regions)
            .map(RecordedMapPoint.Attribution.region)
        return attributions.map {
            RecordedMapPoint(
                coordinate: point.sample.coordinate,
                horizontalAccuracy: point.sample.horizontalAccuracy,
                attribution: $0,
            )
        }
    }
}
