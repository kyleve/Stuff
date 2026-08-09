import Foundation
import PatchlightCore
@_spi(Testing) import StuffCore
import Testing

struct PatchlightScopeTests {
    @Test func signOutDeletesVaultKeyBeforeAccountDataAndPreservesProviderKeys() async throws {
        let credentials = InMemoryCredentialStore()
        let accountID = PatchlightAccountID(rawValue: 2048)
        let setup = try PatchlightCoreTestSupport.makeScope(
            name: #function,
            accountID: accountID,
            credentials: credentials,
        )
        let vaultKey = CredentialKey("account.\(accountID.rawValue).vault-key")
        let providerKey = CredentialKey("provider.openai.api-key")
        let githubKey = CredentialKey("account.\(accountID.rawValue).github-token")
        try credentials.set(Data("provider".utf8), for: providerKey)
        try credentials.set(Data("github".utf8), for: githubKey)
        #expect(try credentials.data(for: vaultKey) != nil)

        try await setup.scope.signOut {
            try credentials.remove(githubKey)
        }

        let accountRoot = setup.root.appendingPathComponent(String(accountID.rawValue))
        #expect(try credentials.data(for: vaultKey) == nil)
        #expect(try credentials.data(for: githubKey) == nil)
        #expect(try credentials.data(for: providerKey) == Data("provider".utf8))
        #expect(!FileManager.default.fileExists(atPath: accountRoot.path))
    }
}
