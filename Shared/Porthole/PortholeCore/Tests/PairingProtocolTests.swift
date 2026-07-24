import CryptoKit
import Foundation
@testable import PortholeCore
import Testing

struct PairingProtocolTests {
    @Test func pairingMessagesRoundTrip() throws {
        let clientKey = Curve25519.KeyAgreement.PrivateKey()
        let messages: [PortholePairingMessage] = [
            .clientHello(mode: .pair(
                clientName: "cli",
                clientPublicKey: clientKey.publicKey.rawRepresentation,
            )),
            .clientHello(mode: .session(pairingID: UUID(), clientNonce: Data([1, 2, 3]))),
            .pairConfirm(mac: Data([9, 9, 9])),
            .pairChallenge(devicePublicKey: Data([4, 5, 6]), salt: Data([7, 8])),
            .pairAccepted(pairingID: UUID(), mac: Data([1])),
            .serverHello(serverNonce: Data([2, 2])),
            .failure(.pairingFailed(.tooManyAttempts)),
        ]
        for message in messages {
            #expect(try jsonRoundTrip(message) == message)
        }
    }

    @Test func publicKeysSurviveRawRepresentationRoundTrip() throws {
        let key = Curve25519.KeyAgreement.PrivateKey()
        let raw = key.publicKey.rawRepresentation
        let restored = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: raw)
        #expect(restored.rawRepresentation == raw)
    }
}
