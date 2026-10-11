import Foundation
import RegionKit
import Testing
@_spi(Testing) import WhereCore
@testable import WhereUI

struct FlightReviewPresentationTests {
    @Test func pointRowsRetainInferenceAndRestoreActionsWithoutDuplicateIdentities() throws {
        let review = PreviewSupport.flightReview(state: .completed)
        let flight = try #require(review.flight)
        let sampleID = review.points[1].sample.id
        let inferred = FlightAssessment(
            id: flight.id,
            startedAt: flight.startedAt,
            lastObservationAt: flight.lastObservationAt,
            lastFlightAt: flight.lastFlightAt,
            airborneSampleIDs: flight.airborneSampleIDs,
            groundSampleIDs: flight.groundSampleIDs,
            peakSpeedKMH: flight.peakSpeedKMH,
            progress: flight.progress,
            inferredEndpoints: [.init(
                sampleID: sampleID,
                reason: .recordingGap(duration: 14400, averageSpeedKMH: 740),
            )],
        )
        let duplicated = GPSCorrectionReview(
            id: review.id,
            day: review.day,
            points: review.points + review.points,
            state: .completed(inferred),
            pointCorrections: review.pointCorrections,
        )
        let display = FlightReviewPresentation(review: duplicated)
        #expect(display.recordedPoints.count == review.points.count)
        let point = try #require(display.recordedPoints.first { $0.id == sampleID })
        #expect(point.evidence == .inferred(.recordingGap(duration: 14400, averageSpeedKMH: 740)))
        #expect(point.point.regions.isEmpty)
        #expect(point.correction?.action == .restoreGPS)
        #expect(point.map.pins.map(\.point.coordinate) == [point.point.sample.coordinate])
        #expect(point.map.pins.map(\.point.attribution) == [.excluded])
        #expect(point.map.routes.isEmpty)
    }

    @Test func correctedAirborneObservationsStayOnTheRoute() {
        let review = PreviewSupport.flightReview(state: .completed)
        let display = FlightReviewPresentation(review: review)
        #expect(review.points.contains { $0.regions.isEmpty })
        #expect(display.map.routes.count == 1)
        #expect(display.map.routes.first?.coordinates == review.points.map(\.sample.coordinate))
        #expect(display.map.pins.count == review.points.count)
        #expect(display.map.pins.contains { $0.point.attribution == .excluded })
    }

    @Test func deviceTracksAndManualAssertionsNeverJoin() {
        let original = PreviewSupport.flightReview(state: .ready)
        let remote = LocationSample(
            timestamp: original.points[0].sample.timestamp,
            coordinate: Coordinate(latitude: 1, longitude: 2),
            horizontalAccuracy: 10,
            source: .gpsVisit,
            recordingDeviceID: RecordingDeviceID(rawValue: UUID()),
        )
        let manual = LocationSample(
            timestamp: remote.timestamp,
            coordinate: Coordinate(latitude: 3, longitude: 4),
            horizontalAccuracy: 10,
            source: .manual,
        )
        let review = GPSCorrectionReview(
            id: original.id,
            day: original.day,
            points: original.points + [
                SampleCorrectionPoint(
                    sample: remote,
                    regions: [.other],
                ),
                SampleCorrectionPoint(
                    sample: manual,
                    regions: [.other],
                ),
            ],
            state: original.state,
            flights: original.flights,
        )
        let display = FlightReviewPresentation(review: review)
        #expect(display.map.routes.count == 2)
        #expect(!display.map.routes.flatMap(\.coordinates).contains(manual.coordinate))
        #expect(display.map.routes.contains { $0.coordinates == [remote.coordinate] })
    }
}
