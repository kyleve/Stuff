import Foundation

/// A confirmation describes one proposed transition and the devices it would leave behind.
public struct DataCompatibilityActivationReview: Sendable, Hashable {
    public struct AffectedDevice: Identifiable, Sendable, Hashable {
        public let id: RecordingDeviceID
        public let displayName: String
        public let supportedVersion: DataCompatibilityVersion?
    }

    public let requiredVersion: DataCompatibilityVersion
    public let previousVersion: DataCompatibilityVersion
    public let generationID: WhereDataGenerationID
    public let affectedDevices: [AffectedDevice]

    public var requiresConfirmation: Bool {
        !affectedDevices.isEmpty
    }
}

/// Background work uses `readyDevicesOnly`. An override is bound to the reviewed transition.
public enum DataCompatibilityActivationApproval: Sendable, Equatable {
    case readyDevicesOnly
    case continueAnyway(DataCompatibilityActivationReview)
}
