import Testing
@testable import ThrowCore

struct AircraftCredentialStoreTests {
    @Test func memoryStoreSavesReplacesAndDeletesCredential() async throws {
        let store = MemoryAircraftCredentialStore(credentials: [:])
        #expect(try await store.state(for: .rapidAPI) == .missing)

        try await store.save(AircraftCredential(secret: "first-1234"), for: .rapidAPI)
        #expect(try await store.state(for: .rapidAPI) == .saved(lastFour: "1234"))

        try await store.save(AircraftCredential(secret: "replacement-9876"), for: .rapidAPI)
        #expect(try await store.state(for: .rapidAPI) == .saved(lastFour: "9876"))

        try await store.delete(.rapidAPI)
        #expect(try await store.credential(for: .rapidAPI) == nil)
    }

    @Test func credentialTrimsInputButNeverDescribesSecret() throws {
        let secret = "sentinel-secret-4321"
        let credential = try AircraftCredential(secret: "  \(secret)\n")
        #expect(credential.lastFour == "4321")
        #expect(String(describing: credential).contains(secret) == false)
        #expect(String(reflecting: credential).contains(secret) == false)
    }

    @Test(arguments: ["a", "ab", "abc", "abcd", "abcdefg"])
    func shortCredentialNeverRevealsWholeValue(secret: String) throws {
        let credential = try AircraftCredential(secret: secret)
        #expect(credential.lastFour == nil)
        #expect(String(describing: credential).contains(secret) == false)
        #expect(String(reflecting: credential).contains(secret) == false)
    }

    @Test func emptyCredentialIsRejected() {
        #expect(throws: AircraftCredentialError.emptyCredential) {
            try AircraftCredential(secret: "   \n")
        }
    }
}
