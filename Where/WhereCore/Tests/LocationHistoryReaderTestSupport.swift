import Foundation
import RegionKit
@_spi(Testing) @testable import WhereCore

/// Uses the production SQLite boundary, explicit recording assignments, and deterministic
/// named geography. Live reporting attribution is deliberately a different region set.
enum LocationHistoryReaderTestSupport {
    static let calendar = SampleCorrectionTestSupport.calendar
    static let policy = RecordingChoiceTestSupport.policy
    static let first = RecordingAssessmentTestSupport.first
    static let second = RecordingAssessmentTestSupport.second

    struct Geography: RegionAttributing {
        let loadedRegions: [Region] = [.california, .newYork]
        func region(at coordinate: Coordinate) -> Region {
            coordinate.longitude < -100 ? .california : .newYork
        }

        func distanceToBoundary(of _: Region, from _: Coordinate) -> Double? {
            nil
        }
    }

    static func reader(_ store: any WhereStore) -> LocationHistoryReader {
        LocationHistoryReader(
            store: store,
            policy: policy,
            geography: HistoryRegionAttribution(catalog: Geography()),
        )
    }

    static func sample(
        seconds: Double,
        deviceID: RecordingDeviceID = first,
        longitude: Double = -122,
        assignment: RecordingDayAssignment? = nil,
        zone: TimeZone = .gmt,
    ) throws -> LocationSample {
        let observation = try RecordingAssessmentTestSupport.observation(
            deviceID: deviceID,
            seconds: seconds,
            longitude: longitude,
            assignment: assignment,
            timeZone: zone,
        )
        return LocationSample(
            id: observation.sample.id,
            timestamp: observation.sample.timestamp,
            coordinate: observation.sample.coordinate,
            horizontalAccuracy: observation.sample.horizontalAccuracy,
            source: observation.sample.source,
            recordingDeviceID: deviceID,
            recordingDay: observation.recordingDay,
        )
    }

    static func projection(
        _ reader: LocationHistoryReader,
        start: Double = 0,
        end: Double = 1201,
    ) async throws -> LocationHistoryProjection {
        try await reader.projection(
            for: .instants(RecordingAssessmentTestSupport.period(start, end)),
            calendar: calendar,
            attributor: RegionAttributor(for: []),
        )
    }

    static func add(_ samples: [LocationSample], to store: SwiftDataStore) async throws {
        try await store.perform {
            for sample in samples {
                try await store.add(sample: sample)
            }
        }
    }
}
