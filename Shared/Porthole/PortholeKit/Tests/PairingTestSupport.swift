import CryptoKit
import Foundation
import PortholeCore
@testable import PortholeKit

/// A mutable, injectable clock for deterministic expiry tests.
final class MutableClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date) {
        current = start
    }

    var now: Date {
        lock.withLock { current }
    }

    func advance(_ interval: TimeInterval) {
        lock.withLock { current += interval }
    }

    func nowClosure() -> @Sendable () -> Date {
        { [weak self] in self?.now ?? Date() }
    }
}

/// Collects the device's published pairing code and lets a test client await it.
actor CodeBox {
    private var code: String?
    private var waiters: [CheckedContinuation<String, Never>] = []

    func set(_ newCode: String?) {
        guard let newCode else { return }
        code = newCode
        for waiter in waiters {
            waiter.resume(returning: newCode)
        }
        waiters.removeAll()
    }

    func waitForCode() async -> String {
        if let code { return code }
        return await withCheckedContinuation { waiters.append($0) }
    }
}

/// A minimal in-process client side of the handshake, for driving
/// `DevicePairingManager` in tests. (The production client is `PortholeClientKit`.)
enum TestPairingClient {
    struct PairingOutcome {
        var pairingID: UUID
        var psk: SymmetricKey
    }

    static func send(
        _ transport: some PortholeTransport,
        _ message: PortholePairingMessage,
    ) async throws {
        try await transport.send(JSONEncoder().encode(message))
    }

    static func receive(_ reader: TransportFrameReader) async throws -> PortholePairingMessage {
        guard let frame = try await reader.next() else { throw PairingTestError.streamEnded }
        return try JSONDecoder().decode(PortholePairingMessage.self, from: frame)
    }

    /// Runs the pair flow, obtaining the code out-of-band via `code`.
    static func pair(
        transport: some PortholeTransport,
        clientName: String,
        code: @Sendable () async -> String,
        overrideCode: (@Sendable (String) -> String)? = nil,
        beforeConfirm: (@Sendable () async -> Void)? = nil,
    ) async throws -> PairingOutcome {
        let reader = TransportFrameReader(transport)
        let clientPrivateKey = Curve25519.KeyAgreement.PrivateKey()
        let clientPublicKey = clientPrivateKey.publicKey.rawRepresentation

        try await send(
            transport,
            .clientHello(mode: .pair(clientName: clientName, clientPublicKey: clientPublicKey)),
        )
        guard case let .pairChallenge(devicePublicKey, salt) = try await receive(reader) else {
            throw PairingTestError.unexpectedMessage
        }

        var codeValue = await code()
        if let overrideCode { codeValue = overrideCode(codeValue) }
        await beforeConfirm?()

        let devicePub = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: devicePublicKey)
        let psk = try PairingCryptography.pairingKey(
            ownPrivateKey: clientPrivateKey,
            peerPublicKey: devicePub,
            salt: salt,
            code: codeValue,
        )
        let mac = PairingCryptography.confirmationCode(
            key: psk,
            clientPublicKey: clientPublicKey,
            devicePublicKey: devicePublicKey,
            salt: salt,
        )
        try await send(transport, .pairConfirm(mac: mac))

        switch try await receive(reader) {
            case let .pairAccepted(pairingID, acceptMac):
                guard PairingCryptography.isValidAcceptance(
                    acceptMac,
                    key: psk,
                    salt: salt,
                    clientPublicKey: clientPublicKey,
                ) else {
                    throw PairingTestError.badAcceptance
                }
                return PairingOutcome(pairingID: pairingID, psk: psk)
            case let .failure(error):
                throw error
            default:
                throw PairingTestError.unexpectedMessage
        }
    }

    /// Runs the session flow with the paired PSK, returning the derived session
    /// key (which should match the device's).
    static func session(
        transport: some PortholeTransport,
        pairingID: UUID,
        psk: SymmetricKey,
    ) async throws -> SymmetricKey {
        let reader = TransportFrameReader(transport)
        let clientNonce = PairingCryptography.randomBytes(count: PairingCryptography.nonceByteCount)
        try await send(
            transport,
            .clientHello(mode: .session(pairingID: pairingID, clientNonce: clientNonce)),
        )
        switch try await receive(reader) {
            case let .serverHello(serverNonce):
                return PairingCryptography.sessionKey(
                    psk: psk,
                    clientNonce: clientNonce,
                    serverNonce: serverNonce,
                )
            case let .failure(error):
                throw error
            default:
                throw PairingTestError.unexpectedMessage
        }
    }
}

extension TestPairingClient {
    /// A 6-digit code guaranteed different from `code` (real code + 1, wrapping).
    static func differentCode(from code: String) -> String {
        let value = Int(code) ?? 0
        return String(format: "%06d", (value + 1) % 1_000_000)
    }
}

enum PairingTestError: Error {
    case streamEnded
    case unexpectedMessage
    case badAcceptance
}
