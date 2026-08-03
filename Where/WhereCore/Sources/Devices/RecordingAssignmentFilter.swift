import Foundation

/// Applies the account-wide recording assignment to raw location samples.
///
/// Assignment changes are append-only and evaluated at each sample timestamp.
/// Legacy samples without a device ID remain visible because no installation
/// can be attributed to them safely.
public enum RecordingAssignmentFilter {
    public static func visibleSamples(
        _ samples: [LocationSample],
        assignmentChanges: [RecordingAssignmentChange],
    ) -> [LocationSample] {
        samples.filter { sample in
            guard sample.source.isGPS, let deviceID = sample.recordingDeviceID else {
                return true
            }
            return RecordingAssignmentChange.resolve(
                assignmentChanges,
                at: sample.timestamp,
            ).permitsRecording(on: deviceID)
        }
    }
}
