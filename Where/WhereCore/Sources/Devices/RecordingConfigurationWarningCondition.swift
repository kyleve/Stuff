import Foundation

/// Evaluates whether this installation's live recording configuration warrants a warning.
public struct RecordingConfigurationWarningCondition: Hashable, Sendable {
    public let isActive: Bool

    public init(
        currentDevice: CurrentRecordingDevice,
        devices: [RecordingDevice],
        automaticRecordingEnabled: Bool?,
        authorizationStatus: LocationAuthorizationStatus,
        now: Date,
    ) {
        let isPrimaryRecordingDevice = RecordingOnboardingRecommendation(
            for: currentDevice,
            devices: devices,
            now: now,
        ).isEnabled
        isActive = isPrimaryRecordingDevice
            && automaticRecordingEnabled == false
            && !authorizationStatus.allowsBackgroundTracking
    }
}
