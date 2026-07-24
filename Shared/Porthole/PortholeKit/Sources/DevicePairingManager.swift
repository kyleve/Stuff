import CryptoKit
import Foundation
import PortholeCore

/// Metadata persisted alongside a pairing PSK (encoded into the credential
/// store's opaque blob) so paired hosts can be listed without the secret.
struct PairedHostMetadata: Codable {
    var name: String
    var createdAt: Date
}

/// The outcome of a connection's handshake.
enum HandshakeResult {
    /// Proceed to an encrypted session with this key.
    case session(key: SymmetricKey, pairingID: UUID)
    /// A pairing completed; the client will reconnect for a session. Close now.
    case paired(pairingID: UUID)
    /// The handshake failed (the reason was already sent to the peer). Close.
    case rejected(PortholeError)
}

/// Owns the device side of the pairing/session handshake and the pending-code
/// lifecycle. Pure of `Network` types so it can be driven over a
/// `LoopbackTransport` in tests. One human code is active at a time; wrong
/// guesses accumulate across attempts and burn it after `maxAttempts`, and it
/// expires after `codeLifetime`.
actor DevicePairingManager {
    private struct ActiveCode {
        var code: String
        var attempts: Int
        var expiresAt: Date
    }

    private let credentials: PortholeCredentialStore
    private let maxAttempts: Int
    private let codeLifetime: TimeInterval
    private let now: @Sendable () -> Date
    private let onCodeChange: @Sendable (String?) async -> Void
    private let onPairedHostsChange: @Sendable () async -> Void

    private var activeCode: ActiveCode?

    init(
        credentials: PortholeCredentialStore,
        maxAttempts: Int = 3,
        codeLifetime: TimeInterval = 120,
        now: @escaping @Sendable () -> Date = { Date() },
        onCodeChange: @escaping @Sendable (String?) async -> Void = { _ in },
        onPairedHostsChange: @escaping @Sendable () async -> Void = {},
    ) {
        self.credentials = credentials
        self.maxAttempts = maxAttempts
        self.codeLifetime = codeLifetime
        self.now = now
        self.onCodeChange = onCodeChange
        self.onPairedHostsChange = onPairedHostsChange
    }

    /// The current paired hosts, read from the credential store.
    func pairedHosts() -> [PairedHost] {
        (try? credentials.all())?.compactMap { record in
            guard let metadata = try? JSONDecoder().decode(
                PairedHostMetadata.self,
                from: record.metadata,
            ) else {
                return PairedHost(
                    pairingID: record.pairingID,
                    name: "Unknown",
                    createdAt: .distantPast,
                )
            }
            return PairedHost(
                pairingID: record.pairingID,
                name: metadata.name,
                createdAt: metadata.createdAt,
            )
        } ?? []
    }

    func revoke(_ pairingID: UUID) throws {
        try credentials.delete(pairingID: pairingID)
    }

    /// Runs the handshake to completion over an established frame reader and raw
    /// frame sender. Sends plaintext pairing frames; on session success the
    /// caller wraps the same reader/sender in a `PortholeSecureChannel`.
    func handshake(
        reader: TransportFrameReader,
        send: @escaping @Sendable (Data) async throws -> Void,
    ) async -> HandshakeResult {
        do {
            guard let helloFrame = try await reader.next() else {
                return .rejected(.notPaired)
            }
            let hello = try JSONDecoder().decode(PortholePairingMessage.self, from: helloFrame)
            guard case let .clientHello(mode) = hello else {
                return .rejected(.invalidParameters("Expected clientHello"))
            }
            switch mode {
                case let .pair(clientName, clientPublicKey):
                    return try await runPairing(
                        clientName: clientName,
                        clientPublicKey: clientPublicKey,
                        reader: reader,
                        send: send,
                    )
                case let .session(pairingID, clientNonce):
                    return try await runSession(
                        pairingID: pairingID,
                        clientNonce: clientNonce,
                        send: send,
                    )
            }
        } catch {
            PortholeLog.network
                .error("Handshake failed: \(String(describing: error), privacy: .public)")
            return .rejected(.invalidParameters(String(describing: error)))
        }
    }

    // MARK: - Pairing

    private func runPairing(
        clientName: String,
        clientPublicKey: Data,
        reader: TransportFrameReader,
        send: @escaping @Sendable (Data) async throws -> Void,
    ) async throws -> HandshakeResult {
        let (code, isNew) = ensureActiveCode()
        if isNew { await onCodeChange(code) }
        let devicePrivateKey = Curve25519.KeyAgreement.PrivateKey()
        let salt = PairingCryptography.randomBytes(count: PairingCryptography.saltByteCount)

        try await send(encode(.pairChallenge(
            devicePublicKey: devicePrivateKey.publicKey.rawRepresentation,
            salt: salt,
        )))

        guard let confirmFrame = try await reader.next() else {
            return .rejected(.pairingFailed(.wrongCode))
        }
        let confirm = try JSONDecoder().decode(PortholePairingMessage.self, from: confirmFrame)
        guard case let .pairConfirm(mac) = confirm else {
            return .rejected(.invalidParameters("Expected pairConfirm"))
        }

        if isExpired() {
            burnCode(); await onCodeChange(nil)
            try await send(encode(.failure(.pairingFailed(.expired))))
            return .rejected(.pairingFailed(.expired))
        }

        let clientPub = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: clientPublicKey)
        let psk = try PairingCryptography.pairingKey(
            ownPrivateKey: devicePrivateKey,
            peerPublicKey: clientPub,
            salt: salt,
            code: code,
        )
        let valid = PairingCryptography.isValidConfirmation(
            mac,
            key: psk,
            clientPublicKey: clientPublicKey,
            devicePublicKey: devicePrivateKey.publicKey.rawRepresentation,
            salt: salt,
        )
        guard valid else {
            let burned = recordFailedAttempt()
            if burned { await onCodeChange(nil) }
            let reason: PairingFailureReason = burned ? .tooManyAttempts : .wrongCode
            try await send(encode(.failure(.pairingFailed(reason))))
            return .rejected(.pairingFailed(reason))
        }

        let pairingID = UUID()
        let metadata = try JSONEncoder().encode(PairedHostMetadata(
            name: clientName,
            createdAt: now(),
        ))
        try credentials.save(pairingID: pairingID, key: psk, metadata: metadata)

        let acceptanceMac = PairingCryptography.acceptanceCode(
            key: psk,
            salt: salt,
            clientPublicKey: clientPublicKey,
        )
        try await send(encode(.pairAccepted(pairingID: pairingID, mac: acceptanceMac)))

        burnCode()
        await onCodeChange(nil)
        await onPairedHostsChange()
        return .paired(pairingID: pairingID)
    }

    // MARK: - Session

    private func runSession(
        pairingID: UUID,
        clientNonce: Data,
        send: @escaping @Sendable (Data) async throws -> Void,
    ) async throws -> HandshakeResult {
        guard let psk = try credentials.key(for: pairingID) else {
            try await send(encode(.failure(.notPaired)))
            return .rejected(.notPaired)
        }
        let serverNonce = PairingCryptography.randomBytes(count: PairingCryptography.nonceByteCount)
        try await send(encode(.serverHello(serverNonce: serverNonce)))
        let sessionKey = PairingCryptography.sessionKey(
            psk: psk,
            clientNonce: clientNonce,
            serverNonce: serverNonce,
        )
        return .session(key: sessionKey, pairingID: pairingID)
    }

    // MARK: - Code lifecycle

    /// Returns the active code (reusing an unexpired one so attempts accumulate),
    /// and whether it was newly minted (so the caller can publish it).
    private func ensureActiveCode() -> (code: String, isNew: Bool) {
        if let active = activeCode, !isExpired() {
            return (active.code, false)
        }
        let code = PairingCryptography.makePairingCode()
        activeCode = ActiveCode(
            code: code,
            attempts: 0,
            expiresAt: now().addingTimeInterval(codeLifetime),
        )
        return (code, true)
    }

    private func isExpired() -> Bool {
        guard let active = activeCode else { return true }
        return now() > active.expiresAt
    }

    /// Records a wrong-code attempt; returns whether the code was burned.
    private func recordFailedAttempt() -> Bool {
        guard var active = activeCode else { return true }
        active.attempts += 1
        activeCode = active
        if active.attempts >= maxAttempts {
            burnCode()
            return true
        }
        return false
    }

    private func burnCode() {
        activeCode = nil
    }

    /// Publishes the current pending code (used to seed UI state on start).
    func currentPendingCode() -> String? {
        guard let active = activeCode, !isExpired() else { return nil }
        return active.code
    }

    private func encode(_ message: PortholePairingMessage) throws -> Data {
        try JSONEncoder().encode(message)
    }
}
