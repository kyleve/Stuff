import Foundation
import Network

/// A Porthole-advertising app found on the local network. The `endpoint` is how
/// the client actually connects; the rest is decoded from the Bonjour TXT
/// record for display and matching.
public struct DiscoveredApp: Sendable, Identifiable, Equatable {
    public var id: String {
        endpointName
    }

    public var endpointName: String
    public var appName: String
    public var bundleID: String
    public var deviceName: String
    public var protocolVersion: Int

    /// The network endpoint to connect to. Not part of identity/equality.
    public var endpoint: NWEndpoint?

    public init(
        endpointName: String,
        appName: String,
        bundleID: String,
        deviceName: String,
        protocolVersion: Int,
        endpoint: NWEndpoint? = nil,
    ) {
        self.endpointName = endpointName
        self.appName = appName
        self.bundleID = bundleID
        self.deviceName = deviceName
        self.protocolVersion = protocolVersion
        self.endpoint = endpoint
    }

    public static func == (lhs: DiscoveredApp, rhs: DiscoveredApp) -> Bool {
        lhs.endpointName == rhs.endpointName
            && lhs.appName == rhs.appName
            && lhs.bundleID == rhs.bundleID
            && lhs.deviceName == rhs.deviceName
            && lhs.protocolVersion == rhs.protocolVersion
    }
}

/// A stored pairing: enough to reconnect (by re-discovering the endpoint) and to
/// show in a list. Persisted as the credential store's metadata blob; the PSK
/// lives beside it under the same pairing id.
public struct PairedApp: Sendable, Codable, Equatable, Identifiable {
    public var id: UUID {
        pairingID
    }

    public var pairingID: UUID
    public var appName: String
    public var bundleID: String
    public var deviceName: String
    public var pairedAt: Date

    public init(
        pairingID: UUID,
        appName: String,
        bundleID: String,
        deviceName: String,
        pairedAt: Date,
    ) {
        self.pairingID = pairingID
        self.appName = appName
        self.bundleID = bundleID
        self.deviceName = deviceName
        self.pairedAt = pairedAt
    }
}
