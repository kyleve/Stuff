import CryptoKit
import Foundation
import os
import PortholeCertificates
import Security

public struct PortholeTrustedPeer: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    public let name: String
    public let certificateDER: Data
    public let enrolledAt: Date
    public var fingerprint: Data {
        Data(SHA256.hash(data: certificateDER))
    }

    public init(id: UUID, name: String, certificateDER: Data, enrolledAt: Date) {
        self.id = id
        self.name = name
        self.certificateDER = certificateDER
        self.enrolledAt = enrolledAt
    }
}

/// Synchronous pin reads serve Network.framework's verifier. The lock serializes Keychain changes
/// and publication of trust.
public final class PortholePeerTrust: Sendable {
    private struct State {
        var peers: [PortholeTrustedPeer]
        var closedSessions: [UUID: Session] = [:]
    }

    private struct Session {
        let peerID: UUID
        let close: @Sendable () -> Void
    }

    private let keychain: PortholeRemoteKeychain?
    private let state: OSAllocatedUnfairLock<State>

    public init(keychain: PortholeRemoteKeychain?) throws {
        self.keychain = keychain
        let data = try keychain?.read(account: "peers")
        let peers = try data
            .map { try JSONDecoder().decode([PortholeTrustedPeer].self, from: $0) } ?? []
        state = OSAllocatedUnfairLock(initialState: State(peers: peers))
    }

    public func peers() -> [PortholeTrustedPeer] {
        state.withLock { $0.peers }
    }

    public func peer(for bytes: Data, at now: Date) throws -> PortholeTrustedPeer? {
        guard try PortholeCertificates.isValid(certificateDER: bytes, at: now)
        else { throw PortholeRemoteError.invalidIdentity }
        return state.withLock { state in state.peers.first { $0.certificateDER == bytes } }
    }

    @discardableResult
    func enroll(_ peer: PortholeTrustedPeer) throws -> PortholeTrustedPeer {
        guard try PortholeCertificates.isValid(
            certificateDER: peer.certificateDER,
            at: peer.enrolledAt,
        )
        else { throw PortholeRemoteError.invalidIdentity }
        return try state.withLock { state in
            if let sameID = state.peers.first(where: { $0.id == peer.id }),
               sameID.certificateDER != peer.certificateDER
            {
                throw PortholeRemoteError.invalidEnrollment
            }
            // Preserve session ownership when a client enrolls the same certificate again.
            let enrolled = PortholeTrustedPeer(
                id: state.peers.first(where: { $0.certificateDER == peer.certificateDER })?
                    .id ?? peer.id,
                name: peer.name,
                certificateDER: peer.certificateDER,
                enrolledAt: peer.enrolledAt,
            )
            var peers = state.peers
                .filter { $0.id != peer.id && $0.certificateDER != peer.certificateDER }
            peers.append(enrolled)
            try keychain?.write(JSONEncoder().encode(peers), account: "peers")
            state.peers = peers
            return enrolled
        }
    }

    public func revoke(peerID: UUID) throws {
        let sessions = try state.withLock { state in
            let peers = state.peers.filter { $0.id != peerID }
            try keychain?.write(JSONEncoder().encode(peers), account: "peers")
            state.peers = peers
            let sessions = state.closedSessions.filter { $0.value.peerID == peerID }
            for session in sessions.keys {
                state.closedSessions[session] = nil
            }
            return sessions.values.map(\.close)
        }
        for close in sessions {
            close()
        }
    }

    func retainSession(id: UUID, peerID: UUID, close: @escaping @Sendable () -> Void) throws {
        try state.withLock { state in
            guard state.peers.contains(where: { $0.id == peerID })
            else { throw PortholeRemoteError.untrustedPeer }
            state.closedSessions[id] = Session(peerID: peerID, close: close)
        }
    }

    func releaseSession(id: UUID) {
        state.withLock { $0.closedSessions[id] = nil }
    }
}

/// The invitation is a credential: the host shows it only in the explicit enrollment UI.
public struct PortholeEnrollmentInvitation: Sendable, Codable, CustomStringConvertible {
    public let serviceName: String
    public let serverCertificatePin: Data
    public let expiresAt: Date
    let token: Data
    public var description: String {
        "PortholeEnrollmentInvitation(<token redacted>)"
    }

    public func encodedInvitation() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(self).base64EncodedString()
    }

    public static func decode(_ value: String) throws -> Self {
        guard value.utf8.count < 8192,
              let data = Data(base64Encoded: value)
        else { throw PortholeRemoteError.invalidEnrollment }
        let invitation = try JSONDecoder().decode(Self.self, from: data)
        guard invitation.token.count == 32,
              invitation.serverCertificatePin.count == 32
        else { throw PortholeRemoteError.invalidEnrollment }
        return invitation
    }
}

struct PortholeEnrollmentRequest: Codable {
    let token: Data
    let clientName: String
    let certificateDER: Data
}

/// A token is consumed before trust persistence. A failure requires fresh explicit enrollment.
public final class PortholeEnrollment: Sendable {
    private let trust: PortholePeerTrust
    private let active = OSAllocatedUnfairLock<PortholeEnrollmentInvitation?>(initialState: nil)

    public init(trust: PortholePeerTrust) {
        self.trust = trust
    }

    public func begin(
        serviceName: String,
        serverCertificatePin: Data,
        at now: Date,
    ) throws -> PortholeEnrollmentInvitation {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { throw PortholeRemoteError.keychain(status) }
        let invitation = PortholeEnrollmentInvitation(
            serviceName: serviceName,
            serverCertificatePin: serverCertificatePin,
            expiresAt: now.addingTimeInterval(120),
            token: Data(bytes),
        )
        active.withLock { $0 = invitation }
        return invitation
    }

    public func cancel() {
        active.withLock { $0 = nil }
    }

    func accept(_ request: PortholeEnrollmentRequest, at now: Date) throws -> PortholeTrustedPeer {
        guard request.token.count == 32, request.certificateDER.count < 64 * 1024,
              !request.clientName.isEmpty,
              request.clientName.utf8.count <= 200
        else { throw PortholeRemoteError.invalidEnrollment }
        return try active.withLock { active in
            guard let invitation = active, invitation.expiresAt > now else {
                active = nil
                throw PortholeRemoteError.enrollmentExpired
            }
            let difference = zip(request.token, invitation.token)
                .reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) }
            guard difference == 0 else { throw PortholeRemoteError.invalidEnrollment }
            active = nil
            let peer = PortholeTrustedPeer(
                id: UUID(),
                name: request.clientName,
                certificateDER: request.certificateDER,
                enrolledAt: now,
            )
            return try trust.enroll(peer)
        }
    }
}
