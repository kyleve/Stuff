import Foundation
import Testing
@testable import ThrowCore

struct AdsBLolSourceTests {
    @Test func requestTransmitsOnlyCoarseCenterAndPaddedRadius() throws {
        let source = AdsBLolSource(
            transport: ScriptedHTTPTransport(outcomes: []),
            decoder: ADSBExchangeV2Decoder(),
            dateProvider: FixedDateProvider(date: ThrowCoreFixture.date),
        )
        let observer = try ThrowCoreFixture.observer(latitude: 37.04, longitude: -122.06)
        let query = try AircraftQuery(
            observer: observer,
            center: observer.coordinate,
            viewport: .map(MapViewport(radius: NauticalMiles(value: 50))),
            includeGroundAircraft: false,
        )
        let request = try source.makeRequest(for: query)
        #expect(request.url.absoluteString == "https://api.adsb.lol/v2/point/37.0/-122.1/60")
        #expect(request.url.absoluteString.contains("37.04") == false)
        #expect(request.timeoutSeconds == 8)
    }

    @Test func snapshotPostFiltersPaddingAgainstExactObserver() async throws {
        let body = ThrowCoreFixture.adsbEnvelope(
            aircraftJSON: """
            {"hex":"near", "lat":37.01, "lon":-122, "alt_baro":10000},
            {"hex":"padded", "lat":37.15, "lon":-122, "alt_baro":10000}
            """,
        )
        let source = AdsBLolSource(
            transport: ScriptedHTTPTransport(
                outcomes: [.response(ThrowCoreFixture.response(data: body))],
            ),
            decoder: ADSBExchangeV2Decoder(),
            dateProvider: FixedDateProvider(date: ThrowCoreFixture.date),
        )
        let snapshot = try await source.snapshot(for: ThrowCoreFixture.mapQuery(radius: 5))
        #expect(snapshot.observations.map(\.id.rawValue) == ["near"])
        #expect(snapshot.successfulHTTPStatus == 200)
    }

    @Test func providerFailureDoesNotExposeResponseBody() async throws {
        let sentinel = "provider-secret-body"
        let source = AdsBLolSource(
            transport: ScriptedHTTPTransport(
                outcomes: [
                    .response(
                        ThrowCoreFixture.response(statusCode: 503, data: Data(sentinel.utf8)),
                    ),
                ],
            ),
            decoder: ADSBExchangeV2Decoder(),
            dateProvider: FixedDateProvider(date: ThrowCoreFixture.date),
        )
        let error = await #expect(throws: AircraftSourceFailure.self) {
            try await source.snapshot(for: ThrowCoreFixture.mapQuery())
        }
        #expect(error == .provider(statusCode: 503, retryAfterSeconds: nil))
        #expect(String(describing: error).contains(sentinel) == false)
    }

    @Test func entirelyMalformedAircraftBodyIsDecodingFailureNotHealthyEmpty() async throws {
        let body = ThrowCoreFixture.adsbEnvelope(
            aircraftJSON: """
            {"hex":"bad", "lat":0, "lon":0, "alt_baro":"not-an-altitude"}
            """,
        )
        let source = AdsBLolSource(
            transport: ScriptedHTTPTransport(
                outcomes: [.response(ThrowCoreFixture.response(data: body))],
            ),
            decoder: ADSBExchangeV2Decoder(),
            dateProvider: FixedDateProvider(date: ThrowCoreFixture.date),
        )

        await #expect(throws: AircraftSourceFailure.decoding) {
            try await source.snapshot(for: ThrowCoreFixture.mapQuery())
        }
    }
}
