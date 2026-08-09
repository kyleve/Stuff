import Foundation
import PatchlightCore
import Testing

struct VaultCipherTests {
    @Test func roundTripsAndAuthenticatesPayloads() throws {
        let cipher = try VaultCipher(keyData: Data(repeating: 7, count: 32))
        let plaintext = Data("review draft".utf8)
        let sealed = try cipher.seal(plaintext)

        #expect(sealed != plaintext)
        #expect(try cipher.open(sealed) == plaintext)

        var corrupt = sealed
        corrupt[corrupt.startIndex] ^= 0x01
        #expect(throws: PatchlightVaultError.authenticationFailed) {
            try cipher.open(corrupt)
        }
    }

    @Test func refusesAKeyWithTheWrongSize() {
        #expect(throws: PatchlightVaultError.invalidKey) {
            try VaultCipher(keyData: Data(repeating: 0, count: 16))
        }
    }
}
