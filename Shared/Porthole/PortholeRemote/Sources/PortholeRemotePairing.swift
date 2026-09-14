import Foundation
import Network

public struct PortholePairedServer: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    public let serviceName: String
    public let certificatePin: Data

    public var endpoint: NWEndpoint {
        .service(
            name: serviceName,
            type: "_porthole._tcp",
            domain: "local.",
            interface: nil,
        )
    }
}

/// Pairing proves possession of a short-lived invitation over a server-pinned TLS connection.
public enum PortholeRemotePairing {
    public static func enroll(
        invitation: PortholeEnrollmentInvitation,
        identity: PortholeTLSIdentity,
        clientName: String,
    ) async throws -> PortholePairedServer {
        guard invitation.expiresAt > Date() else { throw PortholeRemoteError.enrollmentExpired }
        let endpoint = NWEndpoint.service(
            name: invitation.serviceName,
            type: "_porthole-pair._tcp",
            domain: "local.",
            interface: nil,
        )
        let channel = try PortholeConnection(NWConnection(
            to: endpoint,
            using: PortholeTLS.client(identity: nil, serverPin: invitation.serverCertificatePin),
        ))
        defer { channel.cancel() }
        try await channel.start()
        let request = PortholeEnrollmentRequest(
            token: invitation.token,
            clientName: clientName,
            certificateDER: identity.certificateDER,
        )
        try await channel.send(JSONEncoder().encode(request))
        let peer = try await JSONDecoder().decode(PortholeTrustedPeer.self, from: channel.receive())
        guard peer.certificateDER == identity.certificateDER
        else { throw PortholeRemoteError.invalidEnrollment }
        return PortholePairedServer(
            id: peer.id,
            serviceName: invitation.serviceName,
            certificatePin: invitation.serverCertificatePin,
        )
    }
}

extension PortholeRemoteKeychain {
    public func pairedServers() throws -> [PortholePairedServer] {
        guard let data = try read(account: "servers") else { return [] }
        return try JSONDecoder().decode([PortholePairedServer].self, from: data)
    }

    public func save(server: PortholePairedServer) throws {
        var servers = try pairedServers().filter { $0.serviceName != server.serviceName }
        servers.append(server)
        try write(JSONEncoder().encode(servers), account: "servers")
    }

    public func removeServer(serverID: UUID) throws {
        try write(
            JSONEncoder().encode(pairedServers().filter { $0.id != serverID }),
            account: "servers",
        )
    }
}
