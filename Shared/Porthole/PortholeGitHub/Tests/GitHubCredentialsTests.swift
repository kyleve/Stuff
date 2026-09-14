import Foundation
import PortholeGitHub
import Testing

struct GitHubCredentialsTests {
    @Test func credentialDescriptionDoesNotExposeToken() {
        let credential = GitHubCredential(
            account: GitHubTestFixtures.account,
            accessToken: "synthetic-private-token",
            expiresAt: nil,
        )
        #expect(String(describing: credential).contains("synthetic-private-token") == false)
    }

    @Test func keychainRoundTripUsesAnIsolatedSyntheticAccount() async throws {
        let store = GitHubKeychainCredentialStore(service: "Tests.\(UUID().uuidString)")
        let clientID = try GitHubTestFixtures.clientID
        do {
            let credential = GitHubCredential(
                account: GitHubTestFixtures.account,
                accessToken: "synthetic-private-token",
                expiresAt: GitHubTestFixtures.now,
            )
            try await store.save(credential, for: clientID)
            let restored = try await store.credential(for: clientID)
            #expect(restored?.account == credential.account)
            #expect(restored?.expiresAt == credential.expiresAt)
            try await store.remove(for: clientID)
            #expect(try await store.credential(for: clientID) == nil)
        } catch {
            try await store.remove(for: clientID)
            throw error
        }
    }
}
