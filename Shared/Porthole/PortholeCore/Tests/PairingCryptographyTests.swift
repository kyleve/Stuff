import CryptoKit
import Foundation
@testable import PortholeCore
import Testing

struct PairingCryptographyTests {
    @Test func bothSidesDeriveTheSamePairingKeyWithTheSameCode() throws {
        let client = Curve25519.KeyAgreement.PrivateKey()
        let device = Curve25519.KeyAgreement.PrivateKey()
        let salt = PairingCryptography.randomBytes(count: PairingCryptography.saltByteCount)
        let code = "123456"

        let clientKey = try PairingCryptography.pairingKey(
            ownPrivateKey: client,
            peerPublicKey: device.publicKey,
            salt: salt,
            code: code,
        )
        let deviceKey = try PairingCryptography.pairingKey(
            ownPrivateKey: device,
            peerPublicKey: client.publicKey,
            salt: salt,
            code: code,
        )
        #expect(clientKey == deviceKey)
    }

    @Test func aDifferentCodeYieldsADifferentKey() throws {
        let client = Curve25519.KeyAgreement.PrivateKey()
        let device = Curve25519.KeyAgreement.PrivateKey()
        let salt = PairingCryptography.randomBytes(count: PairingCryptography.saltByteCount)

        let right = try PairingCryptography.pairingKey(
            ownPrivateKey: client,
            peerPublicKey: device.publicKey,
            salt: salt,
            code: "000000",
        )
        let wrong = try PairingCryptography.pairingKey(
            ownPrivateKey: device,
            peerPublicKey: client.publicKey,
            salt: salt,
            code: "999999",
        )
        #expect(right != wrong)
    }

    @Test func confirmationCodeVerifies() {
        let key = SymmetricKey(size: .bits256)
        let clientPub = Data("client".utf8)
        let devicePub = Data("device".utf8)
        let salt = Data("salt".utf8)

        let mac = PairingCryptography.confirmationCode(
            key: key,
            clientPublicKey: clientPub,
            devicePublicKey: devicePub,
            salt: salt,
        )
        #expect(PairingCryptography.isValidConfirmation(
            mac,
            key: key,
            clientPublicKey: clientPub,
            devicePublicKey: devicePub,
            salt: salt,
        ))
        // A different key must not verify.
        #expect(!PairingCryptography.isValidConfirmation(
            mac,
            key: SymmetricKey(size: .bits256),
            clientPublicKey: clientPub,
            devicePublicKey: devicePub,
            salt: salt,
        ))
    }

    @Test func acceptanceCodeVerifies() {
        let key = SymmetricKey(size: .bits256)
        let clientPub = Data("client".utf8)
        let salt = Data("salt".utf8)

        let mac = PairingCryptography.acceptanceCode(
            key: key,
            salt: salt,
            clientPublicKey: clientPub,
        )
        #expect(PairingCryptography.isValidAcceptance(
            mac,
            key: key,
            salt: salt,
            clientPublicKey: clientPub,
        ))
        #expect(!PairingCryptography.isValidAcceptance(
            mac,
            key: SymmetricKey(size: .bits256),
            salt: salt,
            clientPublicKey: clientPub,
        ))
    }

    @Test func bothSidesDeriveTheSameSessionKey() {
        let psk = SymmetricKey(size: .bits256)
        let clientNonce = PairingCryptography.randomBytes(count: PairingCryptography.nonceByteCount)
        let serverNonce = PairingCryptography.randomBytes(count: PairingCryptography.nonceByteCount)

        let a = PairingCryptography.sessionKey(
            psk: psk,
            clientNonce: clientNonce,
            serverNonce: serverNonce,
        )
        let b = PairingCryptography.sessionKey(
            psk: psk,
            clientNonce: clientNonce,
            serverNonce: serverNonce,
        )
        #expect(a == b)

        let different = PairingCryptography.sessionKey(
            psk: psk,
            clientNonce: PairingCryptography.randomBytes(count: PairingCryptography.nonceByteCount),
            serverNonce: serverNonce,
        )
        #expect(a != different)
    }

    @Test func pairingCodeIsSixDigitsAndSeedDeterministic() {
        var generator = SeededGenerator(seed: 42)
        let first = PairingCryptography.makePairingCode(using: &generator)
        let isAllDigits = first.allSatisfy(\.isNumber)
        #expect(first.count == 6)
        #expect(isAllDigits)

        var same = SeededGenerator(seed: 42)
        let repeated = PairingCryptography.makePairingCode(using: &same)
        #expect(repeated == first)
    }
}

/// Deterministic RNG for reproducible pairing-code tests.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) {
        state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
