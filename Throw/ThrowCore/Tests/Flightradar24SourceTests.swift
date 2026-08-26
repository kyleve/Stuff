import Foundation
import Testing
@testable import ThrowCore

struct Flightradar24SourceTests {
    @Test func requestUsesBearerContractAndCoarseBounds() throws {
        let token = "fr24-secret-token"
        let source = try makeSource(token: token, outcomes: [])
        let request = try source.makeRequest(for: ThrowCoreFixture.mapQuery(radius: 5))

        #expect(request.url.host() == "fr24api.flightradar24.com")
        #expect(request.url.path() == "/api/live/flight-positions/full")
        #expect(request.url.query()?.contains("bounds=") == true)
        #expect(request.url.absoluteString.contains(token) == false)
        #expect(request.headers[.acceptVersion] == "v1")
        #expect(request.headers[.authorization] == "Bearer \(token)")
        #expect(request.timeoutSeconds == 8)
    }

    @Test func usageRequestUsesBearerContractAndPeriod() throws {
        let token = "fr24-secret-token"
        let source = try makeSource(token: token, outcomes: [])
        let request = try source.makeUsageRequest(period: .last24Hours)

        #expect(request.url.path() == "/api/usage")
        #expect(request.url.query() == "period=24h")
        #expect(request.url.absoluteString.contains(token) == false)
        #expect(request.headers[.acceptVersion] == "v1")
        #expect(request.headers[.authorization] == "Bearer \(token)")
        #expect(request.timeoutSeconds == 8)
    }

    @Test func usageReturnsTheLiveFullPositionReport() async throws {
        let data = Data(
            """
            {"data":[
              {"endpoint":"live/flight-positions/full?{filters}","request_count":12,"credits":2400}
            ]}
            """.utf8,
        )
        let source = try makeSource(
            token: "token",
            outcomes: [.response(ThrowCoreFixture.response(data: data))],
        )

        let report = try await source.usage(period: .last24Hours)

        #expect(report.requestCount == 12)
        #expect(report.credits == 2400)
    }

    @Test func decodesPositionAndRouteFromSameRecord() async throws {
        let data = Data(
            """
            {"data":[{
              "fr24_id":"leg-123","flight":"UAL817","callsign":"UAL817",
              "lat":37.01,"lon":-122.0,"track":182,"alt":12000,
              "gspeed":410,"vspeed":-800,"timestamp":"2023-11-14T22:13:20Z",
              "source":"ADSB","hex":"A1B2C3","type":"B789","reg":"N123UA",
              "painted_as":"UAL","operating_as":"UAL",
              "orig_iata":"SFO","orig_icao":"KSFO","dest_iata":"MEX","dest_icao":"MMMX"
            }]}
            """.utf8,
        )
        let source = try makeSource(
            token: "token",
            outcomes: [.response(ThrowCoreFixture.response(data: data))],
        )

        let snapshot = try await source.snapshot(for: ThrowCoreFixture.mapQuery(radius: 50))
        let observation = try #require(snapshot.observations.first)
        #expect(snapshot.source == .flightradar24)
        #expect(observation.callsign == "UAL817")
        #expect(observation.geometricAltitude == nil)
        #expect(observation.barometricAltitude?.feet == 12000)
        #expect(observation.airborneState == .airborne)
        #expect(observation.metadata.source == .flightradar24)
        #expect(observation.airlineDesignator?.rawValue == "UAL")
        let route = try #require(snapshot.routeResultsByAircraft[observation.id]?.route)
        #expect(route.origin.rawValue == "SFO")
        #expect(route.destination.rawValue == "MEX")
    }

    @Test func paintedCarrierTakesPrecedenceOverOperatingCarrier() throws {
        let data = Data(
            """
            {"data":[{
              "fr24_id":"leg-123","flight":"UA5399","callsign":"SKW5399",
              "lat":37.01,"lon":-122.0,"painted_as":"UAL","operating_as":"SKW"
            }]}
            """.utf8,
        )

        let snapshot = try Flightradar24Decoder().decode(data, fetchedAt: ThrowCoreFixture.date)
        let observation = try #require(snapshot.observations.first)
        #expect(observation.callsign == "UA5399")
        #expect(observation.airlineDesignator?.rawValue == "UAL")
    }

    @Test func operatingCarrierIsUsedWhenPaintedCarrierIsMissing() throws {
        let data = Data(
            """
            {"data":[{
              "fr24_id":"leg-123","flight":"DL3746","callsign":"SKW3746",
              "lat":37.01,"lon":-122.0,"operating_as":"DAL"
            }]}
            """.utf8,
        )

        let snapshot = try Flightradar24Decoder().decode(data, fetchedAt: ThrowCoreFixture.date)
        let observation = try #require(snapshot.observations.first)
        #expect(observation.airlineDesignator?.rawValue == "DAL")
    }

    @Test func radioCallsignSuppliesCarrierWhenExplicitFieldsAreMissing() throws {
        let data = Data(
            """
            {"data":[{
              "fr24_id":"leg-123","flight":"UA817","callsign":"UAL817",
              "lat":37.01,"lon":-122.0
            }]}
            """.utf8,
        )

        let snapshot = try Flightradar24Decoder().decode(data, fetchedAt: ThrowCoreFixture.date)
        let observation = try #require(snapshot.observations.first)
        #expect(observation.callsign == "UA817")
        #expect(observation.airlineDesignator?.rawValue == "UAL")
    }

    @Test func fallsBackToProviderIdentityWhenHexIsMissing() throws {
        let data = Data(
            """
            {"data":[{"fr24_id":"leg-xyz","lat":37.01,"lon":-122.0}]}
            """.utf8,
        )
        let snapshot = try Flightradar24Decoder().decode(data, fetchedAt: ThrowCoreFixture.date)
        let observation = try #require(snapshot.observations.first)
        #expect(observation.id.kind == .providerMarkedNonICAO)
        #expect(snapshot.routeResultsByAircraft[observation.id] == .unavailable)
    }

    @Test(arguments: ["", "   "])
    func ignoresEmptyProviderIdentityWithoutCrashing(fr24ID: String) throws {
        let data = Data(
            """
            {"data":[{"fr24_id":"\(fr24ID)","lat":37.01,"lon":-122.0}]}
            """.utf8,
        )

        #expect(throws: Flightradar24DecodingError.invalidEnvelope) {
            try Flightradar24Decoder().decode(data, fetchedAt: ThrowCoreFixture.date)
        }
    }

    @Test func zeroAltitudeAircraftIsNormalizedAsGroundAndFilteredByQuery() async throws {
        let data = Data(
            """
            {"data":[
              {"fr24_id":"parked","flight":"UAL1","lat":37.01,"lon":-122.0,
               "alt":0,"gspeed":12,"orig_iata":"SFO","dest_iata":"LAX"},
              {"fr24_id":"flying","flight":"UAL2","lat":37.02,"lon":-122.0,
               "alt":12000,"gspeed":410}
            ]}
            """.utf8,
        )
        let source = try makeSource(
            token: "token",
            outcomes: [.response(ThrowCoreFixture.response(data: data))],
        )

        let snapshot = try await source.snapshot(for: ThrowCoreFixture.mapQuery())
        let observation = try #require(snapshot.observations.first)
        #expect(snapshot.observations.count == 1)
        #expect(observation.airborneState == .airborne)
        #expect(snapshot.routeResultsByAircraft[observation.id] == .unavailable)
    }

    @Test(arguments: [
        (401, AircraftSourceFailure.invalidCredential),
        (402, AircraftSourceFailure.subscriptionRequired),
        (403, AircraftSourceFailure.entitlementRejected),
        (429, AircraftSourceFailure.quotaReached(retryAfterSeconds: nil)),
    ])
    func mapsProviderFailure(status: Int, expected: AircraftSourceFailure) async throws {
        let source = try makeSource(
            token: "token",
            outcomes: [.response(ThrowCoreFixture.response(statusCode: status, data: Data()))],
        )
        await #expect(throws: expected) {
            try await source.snapshot(for: ThrowCoreFixture.mapQuery())
        }
    }

    @Test func mapsUsageRateLimitSeparatelyFromThePositionQuota() async throws {
        let source = try makeSource(
            token: "token",
            outcomes: [
                .response(
                    ThrowCoreFixture.response(
                        statusCode: 429,
                        headers: ["Retry-After": "45"],
                        data: Data(),
                    ),
                ),
            ],
        )

        await #expect(
            throws: Flightradar24UsageError.rateLimited(retryAfterSeconds: 45),
        ) {
            try await source.usage(period: .last24Hours)
        }
    }

    private func makeSource(
        token: String,
        outcomes: [ScriptedHTTPOutcome],
    ) throws -> Flightradar24Source {
        try Flightradar24Source(
            transport: ScriptedHTTPTransport(outcomes: outcomes),
            decoder: Flightradar24Decoder(),
            credential: AircraftCredential(secret: token),
            dateProvider: FixedDateProvider(date: ThrowCoreFixture.date),
        )
    }
}
