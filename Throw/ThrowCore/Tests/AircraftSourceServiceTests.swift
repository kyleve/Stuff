import Foundation
import Testing
@testable import ThrowCore

struct AircraftSourceServiceTests {
    @Test func replacementCredentialTestsADSBExchangeWithoutSavingIt() async throws {
        let transport = ScriptedHTTPTransport(outcomes: [.response(
            ThrowCoreFixture.response(
                data: Data(#"{"ac":[],"now":1700000000,"total":0}"#.utf8),
            ),
        )])
        let credentialStore = MemoryAircraftCredentialStore(credentials: [:])
        let service = service(transport: transport, credentialStore: credentialStore)
        let configuration = AircraftSourceConfiguration.adsbExchangeRapidAPI(
            ADSBExchangeConfiguration(
                pollingInterval: .defaultValue,
            ),
        )

        let snapshot = try await service.testConnection(
            configuration: configuration,
            query: ThrowCoreFixture.mapQuery(radius: 5),
            replacementCredential: AircraftCredential(secret: "replacement-secret"),
        )

        #expect(snapshot.observations.isEmpty)
        #expect(try await credentialStore.credential(for: .rapidAPI) == nil)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.url.path().hasSuffix("/dist/5/"))
        #expect(request.headers[.rapidAPIKey] == "replacement-secret")
    }

    @Test func usageUsesTheStoredFlightradar24Credential() async throws {
        let transport = ScriptedHTTPTransport(outcomes: [.response(
            ThrowCoreFixture.response(
                data: Data(
                    #"{"data":[{"endpoint":"live/flight-positions/full?{filters}","request_count":2,"credits":400}]}"#
                        .utf8,
                ),
            ),
        )])
        let credentialStore = try MemoryAircraftCredentialStore(credentials: [
            .flightradar24: AircraftCredential(secret: "stored-token"),
        ])
        let service = service(transport: transport, credentialStore: credentialStore)

        let report = try await service.flightradar24Usage(period: .last24Hours)

        #expect(report.requestCount == 2)
        #expect(report.credits == 400)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.url.path() == "/api/usage")
        #expect(request.headers[.authorization] == "Bearer stored-token")
    }

    @Test func credentialFreeSourceRejectsAReplacementCredential() async throws {
        let transport = ScriptedHTTPTransport(outcomes: [])
        let service = service(
            transport: transport,
            credentialStore: MemoryAircraftCredentialStore(credentials: [:]),
        )

        await #expect(throws: AircraftSourceFailure.invalidConfiguration) {
            try await service.testConnection(
                configuration: .adsbLol,
                query: ThrowCoreFixture.mapQuery(radius: 5),
                replacementCredential: AircraftCredential(secret: "unexpected-secret"),
            )
        }
        #expect(await transport.recordedRequests().isEmpty)
    }

    private func service(
        transport: ScriptedHTTPTransport,
        credentialStore: MemoryAircraftCredentialStore,
    ) -> AircraftSourceService {
        let dateProvider = FixedDateProvider(date: ThrowCoreFixture.date)
        let factory = AircraftSourceFactory(
            cloudTransport: transport,
            localTransport: transport,
            credentialStore: credentialStore,
            dateProvider: dateProvider,
        )
        return AircraftSourceService(
            sourceFactory: factory,
            cloudTransport: transport,
            credentialStore: credentialStore,
            dateProvider: dateProvider,
        )
    }
}
