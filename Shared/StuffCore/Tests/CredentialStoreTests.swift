import Foundation
@_spi(Testing) import StuffCore
import Testing

struct CredentialStoreTests {
    private let tokenKey = CredentialKey("session-token")

    @Test func storesIndependentBinaryValuesByTypedKey() throws {
        let otherKey = CredentialKey("vault-key")
        let store = InMemoryCredentialStore()

        try store.set(Data("token".utf8), for: tokenKey)
        try store.set(Data([0, 1, 2, 255]), for: otherKey)

        #expect(try store.data(for: tokenKey) == Data("token".utf8))
        #expect(try store.data(for: otherKey) == Data([0, 1, 2, 255]))
    }

    @Test func missingAndRemovedValuesAreNil() throws {
        let store = InMemoryCredentialStore()
        #expect(try store.data(for: tokenKey) == nil)

        try store.set(Data("token".utf8), for: tokenKey)
        try store.remove(tokenKey)
        #expect(try store.data(for: tokenKey) == nil)
    }

    @Test func surfacesInjectedTypedFailures() {
        let error = CredentialStoreError(status: errSecInteractionNotAllowed)
        let store = InMemoryCredentialStore(failure: error)

        #expect(throws: error) { try store.data(for: tokenKey) }
        #expect(throws: error) { try store.set(Data(), for: tokenKey) }
        #expect(throws: error) { try store.remove(tokenKey) }
    }

    @Test func credentialKeysRoundTripThroughCodableWithoutLosingIdentity() throws {
        let encoded = try JSONEncoder().encode(tokenKey)
        let decoded = try JSONDecoder().decode(CredentialKey.self, from: encoded)
        #expect(decoded == tokenKey)
    }
}
