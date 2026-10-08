import Foundation
@_spi(Testing) import KeychainKit
import Security
import Testing

struct KeychainStoreTests {
    @Test func errorIdentifiesInteractionNotAllowed() {
        let error = KeychainError(status: errSecInteractionNotAllowed)
        #expect(error.isInteractionNotAllowed)
    }

    @Test func otherErrorsAreNotInteractionNotAllowed() {
        let error = KeychainError(status: errSecDecode)
        #expect(error.isInteractionNotAllowed == false)
    }

    @Test func dataRoundTripsAndCanBeRemoved() throws {
        let store = InMemoryKeychainStore()
        let value = Data([0, 1, 2, 255])

        try store.write(value)
        #expect(try store.read() == value)

        try store.remove()
        #expect(try store.read() == nil)
    }

    @Test func stringsRoundTrip() throws {
        let store = InMemoryKeychainStore()

        try store.write("secret")

        #expect(try store.readString() == "secret")
    }

    @Test func createNeverOverwritesAnExistingItem() throws {
        let original = Data("original".utf8)
        let store = InMemoryKeychainStore(data: original)

        #expect(throws: KeychainError(status: errSecDuplicateItem)) {
            try store.create(Data("replacement".utf8))
        }
        #expect(try store.read() == original)
    }

    @Test func injectedFailuresRemainObservable() {
        let expected = KeychainError(status: errSecInteractionNotAllowed)
        let store = InMemoryKeychainStore(failure: expected)

        #expect(throws: expected) {
            try store.read()
        }
    }
}
