import Foundation

/// Native connection services keep credentials outside presentation and diagnostic values.
public protocol PortholeRemoteConnecting: Sendable {
    func discoveredApplications() -> AsyncThrowingStream<[PortholeDiscoveredApplication], any Error>
    func pairedServers() async throws -> [PortholePairedServer]
    func enroll(invitation: PortholeEnrollmentInvitation, clientName: String) async throws
        -> PortholePairedServer
    func connect(server: PortholePairedServer) async throws -> PortholeRemoteClient
}

public actor PortholeRemoteConnector: PortholeRemoteConnecting {
    private let keychain: PortholeRemoteKeychain
    private let clientName: String

    public init(keychain: PortholeRemoteKeychain, clientName: String) {
        self.keychain = keychain
        self.clientName = clientName
    }

    public func pairedServers() throws -> [PortholePairedServer] {
        try keychain.pairedServers()
    }

    public nonisolated func discoveredApplications()
        -> AsyncThrowingStream<[PortholeDiscoveredApplication], any Error>
    {
        PortholeDiscovery
            .applications()
    }

    public func enroll(
        invitation: PortholeEnrollmentInvitation,
        clientName: String,
    ) async throws -> PortholePairedServer {
        let identity = try keychain.identity(name: self.clientName, at: Date())
        let server = try await PortholeRemotePairing.enroll(
            invitation: invitation,
            identity: identity,
            clientName: clientName,
        )
        // Persist successful remote enrollment even if its presentation has just closed.
        try keychain.save(server: server)
        return server
    }

    public func connect(server: PortholePairedServer) async throws -> PortholeRemoteClient {
        let identity = try keychain.identity(name: clientName, at: Date())
        return try await PortholeRemoteClient.connect(
            endpoint: server.endpoint,
            identity: identity,
            serverPin: server.certificatePin,
        )
    }
}
