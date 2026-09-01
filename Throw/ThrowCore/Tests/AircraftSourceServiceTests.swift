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
        let configuration = ADSBExchangeConfiguration(
            pollingInterval: .defaultValue,
        )
        let request = try AircraftSourceValidationRequest(
            draft: .adsbExchangeRapidAPI(
                configuration,
                replacementCredential: AircraftCredential(secret: "replacement-secret"),
            ),
            query: ThrowCoreFixture.mapQuery(radius: 5),
        )

        let snapshot = try await service.testConnection(
            request: request,
        )

        #expect(snapshot.observations.isEmpty)
        #expect(try await credentialStore.credential(for: .rapidAPI) == nil)
        let recordedRequest = try #require(await transport.recordedRequests().first)
        #expect(recordedRequest.url.path().hasSuffix("/dist/5/"))
        #expect(recordedRequest.headers[.rapidAPIKey] == "replacement-secret")
    }

    @Test func credentialFreeSourceUsesARequestWithoutCredentialState() async throws {
        let transport = ScriptedHTTPTransport(outcomes: [.response(
            ThrowCoreFixture.response(
                data: Data(#"{"ac":[],"now":1700000000,"total":0}"#.utf8),
            ),
        )])
        let service = service(
            transport: transport,
            credentialStore: MemoryAircraftCredentialStore(credentials: [:]),
        )

        let snapshot = try await service.testConnection(
            request: AircraftSourceValidationRequest(
                draft: .adsbLol,
                query: ThrowCoreFixture.mapQuery(radius: 5),
            ),
        )

        #expect(snapshot.observations.isEmpty)
        #expect(await transport.recordedRequests().count == 1)
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
