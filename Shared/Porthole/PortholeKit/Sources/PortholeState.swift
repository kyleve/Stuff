import Foundation

/// A host paired with this device, minus any secret — safe to show in the
/// pairing UI.
public struct PairedHost: Identifiable, Sendable, Equatable {
    public var id: UUID {
        pairingID
    }

    public var pairingID: UUID
    public var name: String
    public var createdAt: Date

    public init(pairingID: UUID, name: String, createdAt: Date) {
        self.pairingID = pairingID
        self.name = name
        self.createdAt = createdAt
    }
}

/// The observable runtime state of a ``Porthole``: what the pairing/status UI
/// binds to. Mutated only by the runtime (hence `internal(set)`); the network
/// layer (advertising, pairing, sessions) fills it in.
@MainActor
@Observable
public final class PortholeState {
    /// Whether the device is currently advertising over Bonjour.
    public internal(set) var isAdvertising: Bool = false
    /// The 6-digit code to read out, non-nil only while a pairing awaits
    /// confirmation.
    public internal(set) var pendingPairingCode: String?
    /// Hosts with a stored pairing.
    public internal(set) var pairedHosts: [PairedHost] = []
    /// How many client sessions are currently connected.
    public internal(set) var activeSessionCount: Int = 0

    public init() {}
}
