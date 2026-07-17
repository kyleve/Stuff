import Foundation
@_spi(Testing) import LedgerCore
import Testing

struct SpendProviderTests {
    @Test func basicAuthPutsTheKeyInTheUsernameWithAnEmptyPassword() {
        // Mirrors `curl -u KEY:` — base64 of "KEY:".
        let expected = "Basic " + Data("secret-key:".utf8).base64EncodedString()
        #expect(CursorSpendAPI.basicAuthValue(apiKey: "secret-key") == expected)
    }

    @Test func scriptedProviderReturnsItsSuccessOutcome() async throws {
        let member = SpendFixture.member(email: "a@b.com", overallSpendCents: 500)
        let provider = ScriptedSpendProvider(member: member)

        let response = try await provider.fetchSpend(apiKey: "ignored")
        #expect(response.teamMemberSpend == [member])
    }

    @Test func scriptedProviderThrowsItsFailureOutcome() async {
        let provider = ScriptedSpendProvider(.failure(.http(401)))

        await #expect(throws: SpendProviderError.http(401)) {
            try await provider.fetchSpend(apiKey: "ignored")
        }
    }
}
