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
        let histories = Dictionary(grouping: policyChanges, by: \.deviceID)

        return samples.filter { sample in
            guard sample.source.isGPS, let deviceID = sample.recordingDeviceID else {
                return true
            }
            // Device-stamped rows fail closed while CloudKit delivery is incomplete. The sample
            // and its installation's policy are separate records, so briefly receiving only the
            // sample must never make an unproven location visible.
            guard let history = histories[deviceID],
                  RecordingPolicyChange.formValidPersistedTimelines(history),
                  RecordingPolicyChange.canonicalTimeline(in: history) != nil
            else {
                return false
            }
            // Account reset is a historical erase boundary, not merely an Off interval. A fix
            // captured before reset but uploaded by an offline device later must stay erased.
            // A subsequent backup replacement intentionally restores historical rows, so only
            // the latest destructive boundary carries this reset floor.
            // Resolve the causally maximal destructive frontier independently from current
            // On/Off authority. A non-destructive re-enable does not clear a reset floor, while a
            // later Replace must name that reset as a parent to retire it. Concurrent reset floors
            // join conservatively at their latest cutoff.
            if let resetFloor = RecordingPolicyChange.activeAccountResetFloor(in: history),
               sample.timestamp <= resetFloor
            {
                return false
            }
            // Evaluate the induced causal DAG at the sample instant. Effective times are monotonic
            // across every parent edge, so future commands can be removed without orphaning an
            // eligible ancestor; concurrent heads still use the safety-first state join.
            guard let latest = RecordingPolicyChange.effectiveHead(
                in: history,
                at: sample.timestamp,
            ) else { return false }
            return latest.isEnabled
        }
    }
}
