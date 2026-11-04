import Foundation

/// Evaluates whether this installation's live recording configuration warrants a warning.
public struct RecordingConfigurationWarningCondition: Hashable, Sendable {
    /// A check-in within 24 hours suppresses the existing no-recorder warning.
    /// This advisory warning does not control setup defaults or recording consent.
    public static let recentActivityWindow: TimeInterval = 24 * 60 * 60
    public let isActive: Bool

    public init(
        currentDevice: CurrentRecordingDevice,
        devices: [RecordingDevice],
        automaticRecordingEnabled: Bool?,
        authorizationStatus: LocationAuthorizationStatus,
        now: Date,
    ) {
        let recentRecorderExists = devices.contains {
            $0.id != currentDevice.id && $0.removedAt == nil
                && $0.lastSeenAt >= now.addingTimeInterval(-Self.recentActivityWindow)
                && ($0.status == .recording || $0.status == .permissionRequired)
        }
        isActive = currentDevice.kind.recommendsAutomaticRecording && !recentRecorderExists
            && automaticRecordingEnabled == false
            && !authorizationStatus.allowsBackgroundTracking
    }
}
