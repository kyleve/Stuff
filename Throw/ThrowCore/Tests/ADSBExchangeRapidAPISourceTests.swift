import Foundation
import Testing
@testable import ThrowCore

struct ADSBExchangeRapidAPISourceTests {
    @Test func requestUsesCurrentRapidAPIContractWithoutCredentialInURL() throws {
        let key = "rapid-secret-key"
        let source = try makeSource(key: key, outcomes: [])
        let request = try source.makeRequest(for: ThrowCoreFixture.mapQuery(radius: 5))
        #expect(
            request.url.absoluteString ==
                "https://adsbexchange-com1.p.rapidapi.com/v2/lat/37.0/lon/-122.0/dist/15/",
        )
        #expect(request.headers[.rapidAPIHost] == ADSBExchangeRapidAPISource.host)
        #expect(request.headers[.rapidAPIKey] == key)
        #expect(request.headers[.acceptEncoding] == "gzip")
        #expect(request.url.absoluteString.contains(key) == false)
        #expect(request.timeoutSeconds == 8)
    }

    @Test func validEmptyResponseIsHealthySuccess() async throws {
        let source = try makeSource(
            key: "key",
            outcomes: [
                .response(
                    ThrowCoreFixture.response(
                        data: ThrowCoreFixture.adsbEnvelope(aircraftJSON: ""),
                    ),
                ),
            ],
        )
        let snapshot = try await source.snapshot(for: ThrowCoreFixture.mapQuery(radius: 5))
        #expect(snapshot.observations.isEmpty)
        #expect(snapshot.source == .adsbExchangeRapidAPI)
        #expect(snapshot.successfulHTTPStatus == 200)
    }

    @Test func credentialTestTransmitsExactlyFiveNauticalMiles() async throws {
        let transport = ScriptedHTTPTransport(outcomes: [
            .response(
                ThrowCoreFixture.response(
                    data: ThrowCoreFixture.adsbEnvelope(aircraftJSON: ""),
                ),
            ),
        ])
        let source = try ADSBExchangeRapidAPISource(
            transport: transport,
            decoder: ADSBExchangeV2Decoder(),
            credential: AircraftCredential(secret: "key"),
            dateProvider: FixedDateProvider(date: ThrowCoreFixture.date),
        )

        let snapshot = try await source.credentialTestSnapshot(
            observer: ThrowCoreFixture.observer(),
        )
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.url.absoluteString.hasSuffix("/dist/5/"))
        #expect(snapshot.observations.isEmpty)
    }

    @Test(arguments: [
        (401, AircraftSourceFailure.invalidCredential),
        (402, AircraftSourceFailure.subscriptionRequired),
        (403, AircraftSourceFailure.entitlementRejected),
        (500, AircraftSourceFailure.provider(statusCode: 500, retryAfterSeconds: nil)),
    ])
    func mapsProviderStatus(statusCode: Int, expected: AircraftSourceFailure) async throws {
        let source = try makeSource(
            key: "key",
            outcomes: [
                .response(ThrowCoreFixture.response(statusCode: statusCode, data: Data())),
            ],
        )
        await #expect(throws: expected) {
            try await source.snapshot(for: ThrowCoreFixture.mapQuery())
        }
    }

    @Test func quotaFailureCarriesLongRetryAfter() async throws {
        let source = try makeSource(
            key: "key",
            outcomes: [
                .response(
                    ThrowCoreFixture.response(
                        statusCode: 429,
                        headers: ["Retry-After": "180"],
                        data: Data(),
                    ),
                ),
            ],
        )
        await #expect(throws: AircraftSourceFailure.quotaReached(retryAfterSeconds: 180)) {
            try await source.snapshot(for: ThrowCoreFixture.mapQuery())
        }
    }

    @Test func transportTimeoutIsRedactedCategory() async throws {
        let source = try makeSource(
            key: "key",
            outcomes: [.failure(HTTPTransportFailure(category: .timedOut))],
        )
        await #expect(throws: AircraftSourceFailure.transport(.timedOut)) {
            try await source.snapshot(for: ThrowCoreFixture.mapQuery())
        }
    }

    @Test func malformedBodyIsCategoryOnlyDecodingFailure() async throws {
        let source = try makeSource(
            key: "key",
            outcomes: [
                .response(ThrowCoreFixture.response(data: Data("secret body".utf8))),
            ],
        )
        await #expect(throws: AircraftSourceFailure.decoding) {
            try await source.snapshot(for: ThrowCoreFixture.mapQuery())
        }
    }

    private func makeSource(
        key: String,
        outcomes: [ScriptedHTTPOutcome],
    ) throws -> ADSBExchangeRapidAPISource {
        try ADSBExchangeRapidAPISource(
            transport: ScriptedHTTPTransport(outcomes: outcomes),
            decoder: ADSBExchangeV2Decoder(),
            credential: AircraftCredential(secret: key),
            dateProvider: FixedDateProvider(date: ThrowCoreFixture.date),
        )
    }
}
