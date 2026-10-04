import Foundation
import RegionKit
@testable import WhereCore

/// A straight invented boundary, with all points independent of private exports.
enum SampleCorrectionAssessmentFixtures {
    struct Boundary: RegionAttributing {
        let loadedRegions: [Region] = [.california, .newYork]
        func region(at coordinate: Coordinate) -> Region {
            coordinate.longitude <= 0 ? .california : .other
        }

        func distanceToBoundary(of region: Region, from coordinate: Coordinate) -> Double? {
            region == .california ? abs(coordinate.longitude) * 111_195 : nil
        }
    }

    static func point(
        _ number: Int,
        minutes: Double,
        longitude: Double,
        accuracy: Double = 5,
        deviceID: RecordingDeviceID? = FlightTrajectoryFixtures.device,
        source: SampleSource = .gpsSignificantChange,
    ) -> LocationSample {
        LocationSample(
            id: FlightTrajectoryFixtures.sampleID(number),
            timestamp: FlightTrajectoryFixtures.date(minutes: minutes),
            coordinate: Coordinate(latitude: 0, longitude: longitude),
            horizontalAccuracy: accuracy,
            source: source,
            recordingDeviceID: deviceID,
        )
    }

    static func reviews(
        _ samples: [LocationSample],
        manuals: [DayPresence] = [],
        attributor: any RegionAttributing = Boundary(),
        now: Date = FlightTrajectoryFixtures.date(minutes: 300),
    ) -> [GPSCorrectionReview] {
        let calendar = SampleCorrectionTestSupport.calendar
        let projection = LocationHistoryProjection(
            samples: AttributedLocationSample.raw(samples, attributor: attributor)
                .sorted { $0.sample.timestamp < $1.sample.timestamp },
            revisions: [],
        )
        let report = SampleCorrectionTestSupport.aggregator.report(
            for: 2026,
            history: projection.samples,
            manualDays: manuals,
        )
        return SampleCorrectionAssessment(attributor: attributor, calendar: calendar).reviews(
            reads: DataIssueReads(
                report: report,
                otherDayCoordinates: [:],
                daySamples: DaySamples(samples: samples, calendar: calendar),
                history: projection,
                manualDays: manuals,
                dataGenerationID: .initial,
                dismissedIssueIDs: [],
                attribution: attributor,
            ),
            primaryRegions: attributor.loadedRegions,
            driftThresholdMeters: 1000,
            now: now,
        )
    }
}
