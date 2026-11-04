import Foundation

/// Local recording default and known replacement candidates. Another phone's activity never
/// disables this phone's recommendation; each installation confirms its own consent.
public struct RecordingOnboardingRecommendation: Sendable, Hashable {
    public let isEnabled: Bool
    public let existingDevices: [RecordingDevice]

    public init(
        for installation: InstallationRecordingContext,
        devices: [RecordingDevice],
    ) {
        existingDevices = devices
            .filter {
                $0.id != installation.currentDevice.id
                    && $0.removedAt == nil
            }
            .sorted { $0.registeredAt == $1.registeredAt
                ? $0.id.rawValue.uuidString < $1.id.rawValue.uuidString
                : $0.registeredAt > $1.registeredAt
            }
        isEnabled = installation.recommendedRecordingEnabled
    }
}
