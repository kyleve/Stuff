import Foundation

/// Applies permanent device-removal cutoffs to raw location samples.
public enum RecordingDeviceRemovalFilter {
    public static func visibleSamples(
        _ samples: [LocationSample],
        removals: [RecordingDeviceRemoval],
    ) -> [LocationSample] {
        let cutoffs = Dictionary(grouping: removals, by: \.deviceID)
            .compactMapValues { $0.map(\.removedAt).min() }
        return samples.filter { sample in
            guard sample.source.isGPS, let deviceID = sample.recordingDeviceID else {
                return true
            }
            guard let cutoff = cutoffs[deviceID] else { return true }
            return sample.timestamp < cutoff
        }
    }
}
