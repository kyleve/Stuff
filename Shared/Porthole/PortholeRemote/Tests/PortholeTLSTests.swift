import Foundation
import Network
@testable import PortholeRemote
import Testing

@Suite(.timeLimit(.minutes(1))) struct PortholeTLSTests {
    @Test func enrolledMutualTLSExchangesBoundedFrames() async throws {
        let now = Date()
        let serverIdentity = try PortholeTLSIdentity.generate(name: "Server", at: now)
        let clientIdentity = try PortholeTLSIdentity.generate(name: "Client", at: now)
        let trust = try PortholePeerTrust(keychain: nil)
        let peer = PortholeTrustedPeer(
            id: UUID(),
            name: "Client",
            certificateDER: clientIdentity.certificateDER,
            enrolledAt: now,
        )
        try trust.enroll(peer)
        let listener = try PortholeNetworkTestListener(parameters: PortholeTLS.server(
            identity: serverIdentity,
            trust: trust,
            enrollment: false,
        ))
        defer { listener.cancel() }
        try await listener.start()
        let port = try #require(listener.listener.port)
        let client = try PortholeConnection(NWConnection(
            host: "127.0.0.1",
            port: port,
            using: PortholeTLS.client(
                identity: clientIdentity,
                serverPin: serverIdentity.fingerprint,
            ),
        ))
        defer { client.cancel() }
        async let connecting: Void = client.start()
        let server = try await listener.accept()
        defer { server.cancel() }
        try await server.start()
        try await connecting
        #expect(try PortholeTLS.peerCertificate(connection: server.network) == clientIdentity
            .certificateDER)
        let payload = Data("TLS1.3 with enrolled peer".utf8)
        try await client.send(payload)
        #expect(try await server.receive() == payload)
        try await server.send(payload)
        #expect(try await client.receive() == payload)
    }

    @Test func enrollmentConnectionPinsServerWithoutSendingAClientIdentity() async throws {
        let serverIdentity = try PortholeTLSIdentity.generate(name: "Server", at: Date())
        let listener = try PortholeNetworkTestListener(parameters: PortholeTLS.server(
            identity: serverIdentity,
            trust: PortholePeerTrust(keychain: nil),
            enrollment: true,
        ))
        defer { listener.cancel() }
        try await listener.start()
        let client = try PortholeConnection(NWConnection(
            host: "127.0.0.1",
            port: #require(listener.listener.port),
            using: PortholeTLS.client(identity: nil, serverPin: serverIdentity.fingerprint),
        ))
        defer { client.cancel() }
        async let connecting: Void = client.start()
        let server = try await listener.accept()
        defer { server.cancel() }
        try await server.start()
        try await connecting
        #expect(throws: PortholeRemoteError.untrustedPeer) {
            try PortholeTLS.peerCertificate(connection: server.network)
        }
        try await client.send(Data("Enrollment only".utf8))
        #expect(try await server.receive() == Data("Enrollment only".utf8))
    }
}
