import Foundation
@_spi(Testing) import LedgerCore
import Testing

@MainActor
struct LedgerServicesTests {
    private func makeServices(
        provider: any SpendProvider = ScriptedSpendProvider(.failure(.network("unused"))),
        keychainSecret: String? = nil,
        email: String? = nil,
    ) -> LedgerServices {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LedgerServicesTests-\(UUID().uuidString)")
        let store = LedgerConfigStore(directory: directory)
        try? store.save(LedgerConfiguration(teamMemberEmail: email, refreshInterval: 900))
        return LedgerServices(
            configStore: store,
            keychain: InMemoryKeychainStore(secret: keychainSecret),
            provider: provider,
            loginItem: LoginItemController(backend: LoginItemRecorder()),
        )
    }

    @Test func startsIdle() {
        let services = makeServices()
        #expect(services.loadState == .idle)
    }

    @Test func failsWithMissingCredentialsWhenNoEmail() async {
        let services = makeServices(keychainSecret: "key", email: nil)
        await services.refresh()
        #expect(services.loadState == .failed(.missingCredentials))
    }

    @Test func failsWithMissingCredentialsWhenNoKey() async {
        let services = makeServices(keychainSecret: nil, email: "me@company.com")
        await services.refresh()
        #expect(services.loadState == .failed(.missingCredentials))
    }

    @Test func loadsTheMatchingMember() async {
        let member = SpendFixture.member(email: "me@company.com", overallSpendCents: 4200)
        let services = makeServices(
            provider: ScriptedSpendProvider(member: member),
            keychainSecret: "key",
            email: "ME@company.com",
        )
        await services.refresh()

        #expect(services.loadState == .loaded(member))
        #expect(services.lastUpdated != nil)
    }

    @Test func failsWithMemberNotFoundWhenNoEmailMatches() async {
        let provider = ScriptedSpendProvider(member: SpendFixture
            .member(email: "someone@company.com"))
        let services = makeServices(
            provider: provider,
            keychainSecret: "key",
            email: "me@company.com",
        )
        await services.refresh()
        #expect(services.loadState == .failed(.memberNotFound))
    }

    @Test func mapsHTTPErrors() async {
        let services = makeServices(
            provider: ScriptedSpendProvider(.failure(.http(401))),
            keychainSecret: "bad-key",
            email: "me@company.com",
        )
        await services.refresh()
        #expect(services.loadState == .failed(.http(401)))
    }

    @Test func mapsNetworkErrors() async {
        let services = makeServices(
            provider: ScriptedSpendProvider(.failure(.network("offline"))),
            keychainSecret: "key",
            email: "me@company.com",
        )
        await services.refresh()
        #expect(services.loadState == .failed(.network("offline")))
    }

    @Test func setAndClearAPIKeyTracksHasAPIKey() throws {
        let services = makeServices()
        #expect(!services.hasAPIKey)

        try services.setAPIKey("new-key")
        #expect(services.hasAPIKey)

        try services.clearAPIKey()
        #expect(!services.hasAPIKey)
    }

    @Test func the401MessageMentionsTheKey() {
        #expect(LedgerServices.LoadError.http(401).message.contains("401"))
        #expect(LedgerServices.LoadError.missingCredentials.message.contains("Settings"))
    }
}
