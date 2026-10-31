import Foundation

/// Installation-owned intent. It is never restored from an account or device backup.
public struct RecordingInstallationControl: Sendable, Equatable {
    /// Existing sidecar encoding. Validation occurs before a record becomes installation state.
    public struct Record: Codable, Sendable {
        let selection: Selection
        let pendingTransition: RecordingAuthorityRecord.Proposal?

        public init(_ value: RecordingInstallationControl) {
            selection = value.selection
            pendingTransition = value.pendingTransition.map(RecordingAuthorityRecord.Proposal.init)
        }

        public var value: RecordingInstallationControl {
            get throws {
                try .init(selection: selection, pendingTransition: pendingTransition?.value)
            }
        }
    }

    /// A user command cannot select the absence of a prior decision.
    public enum RoleChoice: Sendable {
        case secondary
        case recordingRequested

        var selection: Selection {
            switch self {
                case .secondary: .secondary; case .recordingRequested: .recordingRequested
            }
        }
    }

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
        guard let pendingTransition else { return false }
        switch pendingTransition.kind {
            case .transfer, .cancel: return true
            case .claim, .request, .recover, .upgrade: return false
        }
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
        let ownershipID = EventID(rawValue: UUID())
        // A claim from unclaimed authority has no external preconditions.
        do {
            return try RecordingAuthorityProposal(
                state: .unclaimed,
                action: .claim,
                deviceID: deviceID,
                buildVersion: .initial,
                eventID: ownershipID,
            ).result.authority
        } catch {
            preconditionFailure("A fresh fixture claim must be valid: \(error)")
        }
    }
}

extension RecordingAuthorityCoordinator: RecordingAuthorityReading {}
