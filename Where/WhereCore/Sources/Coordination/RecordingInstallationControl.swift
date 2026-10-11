import Foundation

/// Installation-owned intent. It is never restored from an account or device backup.
public struct RecordingInstallationControl: Codable, Sendable, Equatable {
    public enum Selection: String, Codable, Sendable {
        case unconfirmed
        case secondary
        case recordingRequested = "recording-requested"
    }

    public let selection: Selection
    public let pendingTransition: RecordingAuthorityProposal?

    public init(selection: Selection, pendingTransition: RecordingAuthorityProposal?) {
        self.selection = selection
        self.pendingTransition = pendingTransition
    }

    public static let initial = Self(selection: .unconfirmed, pendingTransition: nil)

    public var isRelinquishing: Bool {
        pendingTransition?.kind == .transfer
    }
}

/// Read-only authority boundary consumed by recording. Value snapshots also support previews.
public protocol RecordingAuthorityReading: Sendable {
    func observed() async throws -> RecordingAuthority
}

extension RecordingAuthority: RecordingAuthorityReading {
    public func observed() async throws -> RecordingAuthority {
        self
    }

    @_spi(Demo) @_spi(Testing)
    public static func ownedForTesting(by deviceID: RecordingDeviceID) -> Self {
        let tenure = EventID(rawValue: UUID())
        return .init(
            revision: .init(sequence: 1, eventID: tenure),
            owner: .init(deviceID: deviceID, tenureID: tenure),
            pendingHandoff: nil,
            requiredVersion: .initial,
        )
    }
}

extension RecordingAuthorityCoordinator: RecordingAuthorityReading {}
