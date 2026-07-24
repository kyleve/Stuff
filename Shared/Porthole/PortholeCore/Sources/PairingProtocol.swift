import CryptoKit
import Foundation

/// The plaintext handshake messages exchanged *before* a secure channel exists.
/// They ride the same length-prefixed framing as everything else but are never
/// encrypted — they establish (pair mode) or re-derive (session mode) the key
/// the ``PortholeSecureChannel`` then uses. See the pairing spec in
/// `PortholeCore`'s README.
public enum PortholePairingMessage: Codable, Sendable, Equatable {
    // client → device
    case clientHello(mode: ClientHelloMode)
    case pairConfirm(mac: Data)
    // device → client
    case pairChallenge(devicePublicKey: Data, salt: Data)
    case pairAccepted(pairingID: UUID, mac: Data)
    case serverHello(serverNonce: Data)
    case failure(PortholeError)
}

/// The first frame on any connection: either begin a fresh pairing or resume a
/// session against an existing pairing.
public enum ClientHelloMode: Codable, Sendable, Equatable {
    case pair(clientName: String, clientPublicKey: Data)
    case session(pairingID: UUID, clientNonce: Data)
}

/// Pure, deterministic cryptographic building blocks for pairing and session
/// key derivation — no I/O, no shared state, so the whole handshake is testable
/// in-process. All key agreement is X25519; all derivation is HKDF-SHA256; the
/// session record cipher is ChaCha20-Poly1305 (see ``PortholeSecureChannel``).
public enum PairingCryptography {
    /// Length in bytes of the salt and per-side session nonces.
    public static let saltByteCount = 16
    public static let nonceByteCount = 16

    /// Derives the long-term pre-shared key from the X25519 agreement, the
    /// device's random salt, and the human-entered 6-digit code. Both ends
    /// compute the same key iff they agree on the code.
    public static func pairingKey(
        ownPrivateKey: Curve25519.KeyAgreement.PrivateKey,
        peerPublicKey: Curve25519.KeyAgreement.PublicKey,
        salt: Data,
        code: String,
    ) throws -> SymmetricKey {
        let shared = try ownPrivateKey.sharedSecretFromKeyAgreement(with: peerPublicKey)
        let info = Data("porthole-pair-v1|\(code)".utf8)
        return shared.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: salt,
            sharedInfo: info,
            outputByteCount: 32,
        )
    }

    /// The client's proof it derived the same key: HMAC over
    /// `clientPublicKey || devicePublicKey || salt`.
    public static func confirmationCode(
        key: SymmetricKey,
        clientPublicKey: Data,
        devicePublicKey: Data,
        salt: Data,
    ) -> Data {
        var message = Data()
        message.append(clientPublicKey)
        message.append(devicePublicKey)
        message.append(salt)
        return Data(HMAC<SHA256>.authenticationCode(for: message, using: key))
    }

    public static func isValidConfirmation(
        _ mac: Data,
        key: SymmetricKey,
        clientPublicKey: Data,
        devicePublicKey: Data,
        salt: Data,
    ) -> Bool {
        var message = Data()
        message.append(clientPublicKey)
        message.append(devicePublicKey)
        message.append(salt)
        return HMAC<SHA256>.isValidAuthenticationCode(mac, authenticating: message, using: key)
    }

    /// The device's mutual proof, returned on acceptance: HMAC over
    /// `salt || clientPublicKey`.
    public static func acceptanceCode(
        key: SymmetricKey,
        salt: Data,
        clientPublicKey: Data,
    ) -> Data {
        var message = Data()
        message.append(salt)
        message.append(clientPublicKey)
        return Data(HMAC<SHA256>.authenticationCode(for: message, using: key))
    }

    public static func isValidAcceptance(
        _ mac: Data,
        key: SymmetricKey,
        salt: Data,
        clientPublicKey: Data,
    ) -> Bool {
        var message = Data()
        message.append(salt)
        message.append(clientPublicKey)
        return HMAC<SHA256>.isValidAuthenticationCode(mac, authenticating: message, using: key)
    }

    /// Derives the per-session record-cipher key from the pairing PSK and both
    /// sides' fresh nonces, so a stolen session key never exposes the PSK and
    /// each session is independently keyed.
    public static func sessionKey(
        psk: SymmetricKey,
        clientNonce: Data,
        serverNonce: Data,
    ) -> SymmetricKey {
        var salt = Data()
        salt.append(clientNonce)
        salt.append(serverNonce)
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: psk,
            salt: salt,
            info: Data("porthole-session-v1".utf8),
            outputByteCount: 32,
        )
    }

    /// A fresh zero-padded 6-digit pairing code.
    public static func makePairingCode() -> String {
        var generator = SystemRandomNumberGenerator()
        return makePairingCode(using: &generator)
    }

    /// Seedable variant for deterministic tests.
    public static func makePairingCode(using generator: inout some RandomNumberGenerator)
        -> String
    {
        String(format: "%06d", Int.random(in: 0 ... 999_999, using: &generator))
    }

    /// Cryptographically-random bytes (salt, nonces).
    public static func randomBytes(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        var generator = SystemRandomNumberGenerator()
        for index in bytes.indices {
            bytes[index] = generator.next()
        }
        return Data(bytes)
    }
}
