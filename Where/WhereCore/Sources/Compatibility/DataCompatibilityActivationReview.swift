import Foundation

/// A confirmation describes one proposed transition and the devices it would leave behind.
public struct DataCompatibilityActivationReview: Sendable, Hashable {
    public struct AffectedDevice: Identifiable, Sendable, Hashable {
        public let id: RecordingDeviceID
        public let displayName: String
        public let supportedVersion: DataCompatibilityVersion?

        public init(
            id: RecordingDeviceID,
            displayName: String,
            supportedVersion: DataCompatibilityVersion?,
        ) {
            self.id = id
            self.displayName = displayName
            self.supportedVersion = supportedVersion
        }
    }

    public let requiredVersion: DataCompatibilityVersion
    public let previousVersion: DataCompatibilityVersion
    public let generationID: WhereDataGenerationID
    public let affectedDevices: [AffectedDevice]

    public init(
        requiredVersion: DataCompatibilityVersion,
        previousVersion: DataCompatibilityVersion,
        generationID: WhereDataGenerationID,
        affectedDevices: [AffectedDevice],
    ) {
        self.requiredVersion = requiredVersion
        self.previousVersion = previousVersion
        self.generationID = generationID
        self.affectedDevices = affectedDevices
    }

    public var requiresConfirmation: Bool {
        !affectedDevices.isEmpty
    }

    func requireApproval(_ approval: DataCompatibilityActivationApproval) throws {
        if requiresConfirmation, approval != .continueAnyway(self) {
            throw DataCompatibilityError.confirmationRequired(self)
        }
    }
}

/// Background work uses `readyDevicesOnly`. An override is bound to the reviewed transition.
public enum DataCompatibilityActivationApproval: Sendable, Equatable {
    case readyDevicesOnly
    case continueAnyway(DataCompatibilityActivationReview)
}
