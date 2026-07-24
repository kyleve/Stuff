import CryptoKit
import Foundation
import PortholeCore

/// The Mac-client side of the pairing/session handshake — the mirror of the
/// device's `DevicePairingManager`. Pure of `Network` types so it runs over a
/// `LoopbackTransport` in tests.
enum ClientHandshake {
    struct PairResult {
        var pairingID: UUID
        var psk: SymmetricKey
    }

    /// Runs the pair flow, obtaining the human code via `code` (read from stdin
    /// in the CLI, a text field in the app).
    static func pair(
        reader: TransportFrameReader,
        send: @Sendable (Data) async throws -> Void,
        clientName: String,
        code: @Sendable () async -> String,
    ) async throws -> PairResult {
        let clientPrivateKey = Curve25519.KeyAgreement.PrivateKey()
        let clientPublicKey = clientPrivateKey.publicKey.rawRepresentation

        try await send(encode(.clientHello(mode: .pair(
            clientName: clientName,
            clientPublicKey: clientPublicKey,
        ))))
        guard case let .pairChallenge(devicePublicKey, salt) = try await receive(reader) else {
            throw PortholeClientError.unexpectedResponse
        }

        let codeValue = await code()
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
        try await send(encode(.pairConfirm(mac: mac)))

        switch try await receive(reader) {
            case let .pairAccepted(pairingID, acceptMac):
                guard PairingCryptography.isValidAcceptance(
                    acceptMac,
                    key: psk,
                    salt: salt,
                    clientPublicKey: clientPublicKey,
                ) else {
                    throw PortholeClientError.acceptanceProofFailed
                }
                return PairResult(pairingID: pairingID, psk: psk)
            case let .failure(error):
                throw error
            default:
                throw PortholeClientError.unexpectedResponse
        }
    }

    /// Runs the session flow, returning the per-session key both ends derive.
    static func session(
        reader: TransportFrameReader,
        send: @Sendable (Data) async throws -> Void,
        pairingID: UUID,
        psk: SymmetricKey,
    ) async throws -> SymmetricKey {
        let clientNonce = PairingCryptography.randomBytes(count: PairingCryptography.nonceByteCount)
        try await send(encode(.clientHello(mode: .session(
            pairingID: pairingID,
            clientNonce: clientNonce,
        ))))
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
                throw PortholeClientError.unexpectedResponse
        }
    }

    private static func encode(_ message: PortholePairingMessage) throws -> Data {
        try JSONEncoder().encode(message)
    }

    private static func receive(_ reader: TransportFrameReader) async throws
        -> PortholePairingMessage
    {
        guard let frame = try await reader.next()
        else { throw PortholeClientError.connectionClosed }
        return try JSONDecoder().decode(PortholePairingMessage.self, from: frame)
    }
}

/// Failures surfaced by the Mac client.
public enum PortholeClientError: Error, Sendable, Equatable {
    case unexpectedResponse
    case acceptanceProofFailed
    case connectionClosed
    case notPaired
    case deviceNotFound
    case connectionFailed(String)
}
