import Foundation
import RegionKit
import WhereCore

/// Optional local verification inputs. Private archives and expected identities
/// are supplied outside the checkout and never become repository fixtures.
struct FlightArchiveVerificationConfiguration: Decodable {
    let backupPath: String
    let from: Date
    let until: Date
    let now: Date
    let cruiseCheckAt: Date
    let awaitingArrivalCheckAt: Date
    let expectedArrivalAt: Date
    let expectedArrivalConfirmedAt: Date
    let expectedInputSampleCount: Int
    let expectedAirborneSampleIDs: Set<UUID>
    let expectedPreservedSampleIDs: Set<UUID>
    let calendarTimeZoneID: String
    let expectedResultingRegions: Set<Region>
}

/// An invented equatorial route, not exported personal location history. Its
/// structure exercises short callbacks, a recording gap, a turning approach,
/// and delayed arrival confirmation without retaining a real itinerary.
enum FlightTrajectoryFixtures {
    static let start = Date(timeIntervalSince1970: 1_767_225_600)
    static let device = RecordingDeviceID(rawValue: sampleID(9000))

    struct Trace {
        let samples: [LocationSample]
        let departureNoiseID: UUID
        let shortIntervalID: UUID
        let lastCruiseAt: Date
        let firstGroundAt: Date
        let readyAt: Date
    }

    struct SparseLayoverTrace {
        let samples: [LocationSample]
        let layoverSampleIDs: Set<UUID>
        let airborneSampleIDs: Set<UUID>
        let firstGroundAt: Date
        let readyAt: Date
    }

    static func sampleID(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!
    }

    static func date(minutes: Double) -> Date {
        start.addingTimeInterval(minutes * 60)
    }

    static func sample(
        _ number: Int,
        minutes: Double,
        east: Double,
        north: Double = 0,
        accuracy: Double = 5,
        deviceID: RecordingDeviceID? = device,
        source: SampleSource = .gpsSignificantChange,
        motion: LocationMotion? = nil,
    ) -> LocationSample {
        LocationSample(
            id: sampleID(number),
            timestamp: date(minutes: minutes),
            coordinate: Coordinate(latitude: north / 111.195, longitude: east / 111.195),
            horizontalAccuracy: accuracy,
            source: source,
            recordingDeviceID: deviceID,
            motion: motion,
        )
    }

    static func turningFlight() -> Trace {
        Trace(
            samples: [
                sample(1, minutes: 0, east: 0),
                sample(2, minutes: 5, east: 0),
                sample(3, minutes: 10, east: 0),
                sample(4, minutes: 11, east: 1),
                sample(5, minutes: 15, east: 5),
                sample(6, minutes: 20, east: 45),
                sample(7, minutes: 25, east: 120),
                sample(8, minutes: 25 + 5.0 / 60, east: 121.25),
                sample(9, minutes: 30, east: 195),
                sample(10, minutes: 105, east: 1320),
                sample(11, minutes: 110, east: 1395),
                sample(12, minutes: 115, east: 1470),
                // A turn away from the eventual arrival, then back toward it.
                sample(13, minutes: 120, east: 1490, north: -5),
                sample(14, minutes: 125, east: 1462, north: -8),
                sample(15, minutes: 130, east: 1444, north: 8),
                sample(16, minutes: 135, east: 1445, north: 8),
                sample(17, minutes: 140, east: 1445, north: 8),
                sample(18, minutes: 145, east: 1445, north: 8),
            ],
            departureNoiseID: sampleID(4),
            shortIntervalID: sampleID(8),
            lastCruiseAt: date(minutes: 115),
            firstGroundAt: date(minutes: 130),
            readyAt: date(minutes: 140),
        )
    }

    /// Two stationary observations cannot confirm a dwell, but they must keep
    /// their presence when the surrounding cruise segments are corrected.
    static func sparseLayover() -> SparseLayoverTrace {
        SparseLayoverTrace(
            samples: [
                sample(1, minutes: 0, east: 0),
                sample(2, minutes: 5, east: 75),
                sample(3, minutes: 10, east: 150),
                sample(4, minutes: 30, east: 150),
                sample(5, minutes: 35, east: 225),
                sample(6, minutes: 40, east: 300),
                sample(7, minutes: 45, east: 300),
                sample(8, minutes: 50, east: 300),
            ],
            layoverSampleIDs: [sampleID(3), sampleID(4)],
            airborneSampleIDs: [sampleID(2), sampleID(5)],
            firstGroundAt: date(minutes: 40),
            readyAt: date(minutes: 50),
        )
    }

    struct SeparatedFlightsTrace {
        let samples: [LocationSample]
        let earlierLastObservationAt: Date
        let laterStartedAt: Date
        let laterFirstGroundAt: Date
        let readyAt: Date
    }

    /// Recording stops during one flight and resumes on a separate trip three days later.
    static func separatedFlights(laterStartsWithTransition: Bool) -> SeparatedFlightsTrace {
        let earlier = turningFlight()
        let laterStart = 3.0 * 24 * 60
        var later = [
            sample(101, minutes: laterStart, east: 0),
            sample(102, minutes: laterStart + 5, east: 20),
            sample(103, minutes: laterStart + 10, east: 95),
            sample(104, minutes: laterStart + 15, east: 170),
            sample(105, minutes: laterStart + 20, east: 170),
            sample(106, minutes: laterStart + 25, east: 170),
        ]
        if !laterStartsWithTransition { later.removeFirst() }
        return SeparatedFlightsTrace(
            samples: earlier.samples.filter { $0.timestamp <= earlier.lastCruiseAt } + later,
            earlierLastObservationAt: earlier.lastCruiseAt,
            laterStartedAt: date(minutes: laterStart + (laterStartsWithTransition ? 0 : 5)),
            laterFirstGroundAt: date(minutes: laterStart + 15),
            readyAt: date(minutes: laterStart + 25),
        )
    }

    static func replacing(
        _ sample: LocationSample,
        timestamp: Date? = nil,
        motion: LocationMotion? = nil,
    ) -> LocationSample {
        LocationSample(
            id: sample.id,
            timestamp: timestamp ?? sample.timestamp,
            coordinate: sample.coordinate,
            horizontalAccuracy: sample.horizontalAccuracy,
            source: sample.source,
            recordingDeviceID: sample.recordingDeviceID,
            motion: motion,
        )
    }
}
