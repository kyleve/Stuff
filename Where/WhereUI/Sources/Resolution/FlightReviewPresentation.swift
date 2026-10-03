import Foundation
import RegionKit
import WhereCore

/// Builds map geometry and edit lookups once for each accepted review value.
struct FlightReviewPresentation {
    let review: GPSCorrectionReview
    let map: RecordedMapData
    let editedPoints: [SampleCorrectionPoint]
    let replacements: [LocationSample.ID: Set<Region>]

    init(review: GPSCorrectionReview) {
        self.review = review
        let points = review.points.sorted {
            if $0.sample.timestamp != $1.sample
                .timestamp { return $0.sample.timestamp < $1.sample.timestamp }
            return $0.sample.id < $1.sample.id
        }
        let mapPoints = points.flatMap { point in
            // Excluded airborne fixes remain visible as raw observations on the review map.
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
    }
}
