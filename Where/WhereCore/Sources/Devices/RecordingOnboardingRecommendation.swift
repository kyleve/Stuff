import Foundation

/// Advisory first-run choice derived from recently synced device status.
public struct RecordingOnboardingRecommendation: Sendable, Hashable {
    public static let recentActivityWindow: TimeInterval = 24 * 60 * 60

    public let isEnabled: Bool
    public let recentRecordingDevice: RecordingDevice?

    public init(isEnabled: Bool, recentRecordingDevice: RecordingDevice?) {
        self.isEnabled = isEnabled
        self.recentRecordingDevice = recentRecordingDevice
    }

    public init(
        for installation: CurrentRecordingDevice,
        devices: [RecordingDevice],
        now: Date,
    ) {
        let cutoff = now.addingTimeInterval(-Self.recentActivityWindow)
        let recent = devices
            .filter {
                $0.id != installation.id
                    && $0.removedAt == nil
                    && $0.lastSeenAt >= cutoff
                    && ($0.status == .recording || $0.status == .permissionRequired)
            }
            .max { $0.lastSeenAt < $1.lastSeenAt }
        recentRecordingDevice = recent
        isEnabled = installation.kind.recommendsAutomaticRecording && recent == nil
    }
}
