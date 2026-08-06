import Foundation
@_spi(Testing) import LedgerCore
import Testing

struct KeychainStoreTests {
    @Test func readsBackWhatItWrites() throws {
        let store = InMemoryKeychainStore()
        #expect(try store.read() == nil)

        try store.write("api-key-123")
        #expect(try store.read() == "api-key-123")
    }

    @Test func writingWhitespaceRemovesTheSecret() throws {
        let store = InMemoryKeychainStore(secret: "existing")
        try store.write("   ")
        #expect(try store.read() == nil)
    }

    @Test func writeTrimsSurroundingWhitespace() throws {
        let store = InMemoryKeychainStore()
        try store.write("  padded-key\n")
        #expect(try store.read() == "padded-key")
    }

    @Test func removeClearsTheSecret() throws {
        let store = InMemoryKeychainStore(secret: "existing")
        try store.remove()
        #expect(try store.read() == nil)
    }

    @Test func surfacesInjectedFailures() {
        let store = InMemoryKeychainStore(failure: KeychainError(status: -25300))
        #expect(throws: KeychainError.self) { try store.read() }
    }
}
