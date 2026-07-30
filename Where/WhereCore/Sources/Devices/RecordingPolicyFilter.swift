import Foundation

/// Applies device recording policy to raw location samples.
///
/// Policy changes are append-only and evaluated at each sample timestamp.
/// Legacy samples without a device ID remain visible because no device policy
/// can be attributed to them safely.
public enum RecordingPolicyFilter {
    public static func visibleSamples(
        _ samples: [LocationSample],
        policyChanges: [RecordingPolicyChange],
    ) -> [LocationSample] {
        let timelines = Dictionary(grouping: policyChanges, by: \.deviceID)
            .mapValues { $0.sorted(by: RecordingPolicyChange.isOrderedBefore) }

        return samples.filter { sample in
            guard sample.source.isGPS, let deviceID = sample.recordingDeviceID else {
                return true
            }
            guard let timeline = timelines[deviceID] else {
                return true
            }
            let latest = timeline.last { change in
                change.effectiveAt <= sample.timestamp
            }
            return latest?.isEnabled ?? true
        }
    }
}
