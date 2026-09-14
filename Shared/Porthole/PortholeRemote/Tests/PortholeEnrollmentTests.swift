import Foundation
@testable import PortholeRemote
import Testing

struct PortholeEnrollmentTests {
    @Test func reenrollmentPreservesOwnershipOfExistingSessions() throws {
        let trust = try PortholePeerTrust(keychain: nil)
        let now = Date()
        let identity = try PortholeTLSIdentity.generate(name: "Client", at: now)
        let first = try trust.enroll(.init(
            id: UUID(),
            name: "Original",
            certificateDER: identity.certificateDER,
            enrolledAt: now,
        ))
        let closed = PortholeRemoteTestCounter()
        try trust.retainSession(id: UUID(), peerID: first.id, close: { closed.increment() })
        let renewed = try trust.enroll(.init(
            id: UUID(),
            name: "Renamed",
            certificateDER: identity.certificateDER,
            enrolledAt: now,
        ))
        #expect(renewed.id == first.id)
        #expect(trust.peers().count == 1)
        try trust.revoke(peerID: renewed.id)
        #expect(closed.count == 1)
    }

    @Test func invitationIsSingleUseAndWrongTokenDoesNotConsumeIt() throws {
        let trust = try PortholePeerTrust(keychain: nil)
        let enrollment = PortholeEnrollment(trust: trust)
        let now = Date()
        let identity = try PortholeTLSIdentity.generate(name: "Client", at: now)
        let invitation = try enrollment.begin(
            serviceName: "Test",
            serverCertificatePin: identity.fingerprint,
            at: now,
        )
        #expect(invitation.token.count == 32)
        let decoded = try PortholeEnrollmentInvitation.decode(invitation.encodedInvitation())
        #expect(decoded.token == invitation.token)
        let wrong = PortholeEnrollmentRequest(
            token: Data(repeating: 0, count: 32),
            clientName: "Client",
            certificateDER: identity.certificateDER,
        )
        #expect(throws: PortholeRemoteError.invalidEnrollment) { try enrollment.accept(
            wrong,
            at: now,
        ) }
        let request = PortholeEnrollmentRequest(
            token: invitation.token,
            clientName: "Client",
            certificateDER: identity.certificateDER,
        )
        let peer = try enrollment.accept(request, at: now)
        #expect(try trust.peer(for: identity.certificateDER, at: now)?.id == peer.id)
        #expect(throws: PortholeRemoteError.enrollmentExpired) { try enrollment.accept(
            request,
            at: now,
        ) }
    }

    @Test func expiryAndCancellationRejectInvitation() throws {
        let trust = try PortholePeerTrust(keychain: nil)
        let enrollment = PortholeEnrollment(trust: trust)
        let now = Date()
        let identity = try PortholeTLSIdentity.generate(name: "Client", at: now)
        let invitation = try enrollment.begin(
            serviceName: "Test",
            serverCertificatePin: identity.fingerprint,
            at: now,
        )
        let request = PortholeEnrollmentRequest(
            token: invitation.token,
            clientName: "Client",
            certificateDER: identity.certificateDER,
        )
        #expect(throws: PortholeRemoteError.enrollmentExpired) { try enrollment.accept(
            request,
            at: now.addingTimeInterval(120),
        ) }
        _ = try enrollment.begin(
            serviceName: "Test",
            serverCertificatePin: identity.fingerprint,
            at: now,
        )
        enrollment.cancel()
        #expect(throws: PortholeRemoteError.enrollmentExpired) { try enrollment.accept(
            request,
            at: now,
        ) }
        #expect(trust.peers().isEmpty)
    }

    @Test func revocationClosesOnlyThatPeersSessionsAndCannotRaceRegistration() throws {
        let trust = try PortholePeerTrust(keychain: nil)
        let now = Date()
        let first = try PortholeTrustedPeer(
            id: UUID(),
            name: "First",
            certificateDER: PortholeTLSIdentity.generate(name: "First", at: now).certificateDER,
            enrolledAt: now,
        )
        let second = try PortholeTrustedPeer(
            id: UUID(),
            name: "Second",
            certificateDER: PortholeTLSIdentity.generate(name: "Second", at: now).certificateDER,
            enrolledAt: now,
        )
        try trust.enroll(first); try trust.enroll(second)
        let firstClosed = PortholeRemoteTestCounter()
        let secondClosed = PortholeRemoteTestCounter()
        try trust.retainSession(id: UUID(), peerID: first.id, close: { firstClosed.increment() })
        try trust.retainSession(id: UUID(), peerID: second.id, close: { secondClosed.increment() })
        try trust.revoke(peerID: first.id)
        #expect(firstClosed.count == 1)
        #expect(secondClosed.count == 0)
        #expect(try trust.peer(for: first.certificateDER, at: now) == nil)
        #expect(throws: PortholeRemoteError.untrustedPeer) { try trust.retainSession(
            id: UUID(),
            peerID: first.id,
            close: {},
        ) }
    }
}
