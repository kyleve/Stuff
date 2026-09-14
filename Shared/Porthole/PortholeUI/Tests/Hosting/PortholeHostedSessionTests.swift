import Foundation
import PortholeCore
import PortholeRemote
@testable import PortholeUI
import Testing

@MainActor
struct PortholeHostedSessionTests {
    @Test func newPeerConsumesTheDisplayedInvitation() async throws {
        let host = EnrollmentHost(expiresAt: Date().addingTimeInterval(120))
        let session = PortholeHostedSession(server: host)
        await session.refresh()
        await session.createInvitation()
        guard case let .invitation(invitation) = session.enrollment else {
            Issue.record("Expected a displayed invitation"); return
        }
        #expect(try PortholeEnrollmentInvitation.decode(invitation.text).serviceName == "Fixture")
        #expect(invitation.image != nil)
        await host.addPeer()
        await session.refresh()
        guard case .closed = session.enrollment else {
            Issue.record("Consumed invitation remained visible"); return
        }
        #expect(await host.cancellations == 1)
        #expect(session.peers.count == 1)
    }

    @Test func expiryClosesEnrollmentAndRevocationUsesTheSelectedPeer() async throws {
        let host = EnrollmentHost(expiresAt: Date(timeIntervalSince1970: 0))
        let session = PortholeHostedSession(server: host)
        await host.addPeer()
        await session.refresh()
        await session.createInvitation()
        await session.refresh()
        guard case .closed = session.enrollment else {
            Issue.record("Expired invitation remained visible"); return
        }
        let peer = try #require(session.peers.first)
        await session.revoke(peer)
        #expect(await host.revoked == peer.id)
        #expect(session.peers.isEmpty)
    }
}

private actor EnrollmentHost: PortholeHosting {
    let expiresAt: Date
    private var enrolled: [PortholeTrustedPeer] = []
    private(set) var cancellations = 0
    private(set) var revoked: UUID?

    init(expiresAt: Date) {
        self.expiresAt = expiresAt
    }

    func start() {}
    func stop() {}
    func beginEnrollment() throws -> PortholeEnrollmentInvitation {
        try PortholeValue.object([
            "serviceName": .string("Fixture"),
            "serverCertificatePin": .string(Data(repeating: 1, count: 32).base64EncodedString()),
            "token": .string(Data(repeating: 2, count: 32).base64EncodedString()),
            "expiresAt": .number(expiresAt.timeIntervalSinceReferenceDate),
        ]).decode(PortholeEnrollmentInvitation.self)
    }

    func cancelEnrollment() {
        cancellations += 1
    }

    func peers() -> [PortholeTrustedPeer] {
        enrolled
    }

    func addPeer() {
        enrolled.append(.init(id: UUID(), name: "Mac", certificateDER: Data(), enrolledAt: Date()))
    }

    func revoke(peerID: UUID) {
        revoked = peerID; enrolled.removeAll { $0.id == peerID }
    }
}
