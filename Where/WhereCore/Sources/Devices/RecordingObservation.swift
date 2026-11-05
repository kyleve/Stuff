import Foundation
import RegionKit

/// Validated GPS input for the replacement resolver. Region lookup occurs against the full
/// catalog before construction; nil means unresolved geography, never the reporting group Other.
public struct RecordingObservation: Hashable, Sendable {
    public enum ValidationError: Error {
        case unattributedGPS
        case invalidMeasurement
        case reportingRegion
        case inconsistentRecordingDay
        case missingRecordingDay
    }

    public let sample: LocationSample
    public let deviceID: RecordingDeviceID
    public let recordingDay: RecordingDayAssignment
    public let geography: RecordingGeography

    public var region: Region? {
        geography.singleRegion
    }

    public init(
        sample: LocationSample,
        recordingDay: RecordingDayAssignment,
        region: Region?,
    ) throws {
        guard region != .other else { throw ValidationError.reportingRegion }
        try self.init(
            sample: sample,
            recordingDay: recordingDay,
            geography: RecordingGeography(
                knownRegions: Set(region.map { [$0] } ?? []),
                includesUnknownPresence: region == nil,
            ),
        )
    }

    public init(
        sample: LocationSample,
        recordingDay: RecordingDayAssignment,
        geography: RecordingGeography,
    ) throws {
        guard sample.source.isGPS, let deviceID = sample.recordingDeviceID else {
            throw ValidationError.unattributedGPS
        }
        guard sample.timestamp.timeIntervalSinceReferenceDate.isFinite,
              sample.horizontalAccuracy.isFinite, sample.horizontalAccuracy >= 0,
              sample.coordinate.latitude.isFinite, sample.coordinate.longitude.isFinite,
              (-90 ... 90).contains(sample.coordinate.latitude),
              (-180 ... 180).contains(sample.coordinate.longitude)
        else { throw ValidationError.invalidMeasurement }
        if case let .resolved(context) = recordingDay {
            guard context.matches(observedAt: sample.timestamp) else {
                throw ValidationError.inconsistentRecordingDay
            }
        }
        self.sample = sample
        self.deviceID = deviceID
        self.recordingDay = recordingDay
        self.geography = geography
    }
}
