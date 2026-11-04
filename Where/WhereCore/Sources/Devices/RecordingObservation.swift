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
    }

    public let sample: LocationSample
    public let deviceID: RecordingDeviceID
    public let recordingDay: RecordingDayAssignment
    public let region: Region?

    public init(
        sample: LocationSample,
        recordingDay: RecordingDayAssignment,
        region: Region?,
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
        guard region != .other else { throw ValidationError.reportingRegion }
        if case let .resolved(context) = recordingDay {
            let expected = try RecordingDayAssignment.Context(
                observedAt: sample.timestamp,
                timeZone: context.timeZone,
            )
            guard context == expected else { throw ValidationError.inconsistentRecordingDay }
        }
        self.sample = sample
        self.deviceID = deviceID
        self.recordingDay = recordingDay
        self.region = region
    }
}
