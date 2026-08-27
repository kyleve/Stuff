import Foundation
import Testing
@testable import ThrowCore

struct Flightradar24SourceTests {
    @Test func antimeridianResponsesMergeFreshestAircraftAndMatchingRoute() async throws {
        let staleData = Data(
            """
            {"data":[
              {"fr24_id":"duplicate","lat":0.0,"lon":179.9,
               "timestamp":"2023-11-14T22:13:10Z","orig_iata":"DEL","dest_iata":"EWR"},
              {"fr24_id":"western","lat":0.0,"lon":-179.9,
               "timestamp":"2023-11-14T22:13:20Z"}
            ]}
            """.utf8,
        )
        let freshData = Data(
            """
            {"data":[
              {"fr24_id":"duplicate","lat":0.1,"lon":179.95,
               "timestamp":"2023-11-14T22:13:20Z","orig_iata":"SFO","dest_iata":"NRT"},
              {"fr24_id":"eastern","lat":0.0,"lon":179.7,
               "timestamp":"2023-11-14T22:13:20Z"}
            ]}
            """.utf8,
        )
        let transport = ScriptedHTTPTransport(outcomes: [
            .response(ThrowCoreFixture.response(data: staleData)),
            .response(ThrowCoreFixture.response(data: freshData)),
        ])
        let source = try makeSource(token: "token", transport: transport)

        let snapshot = try await source.snapshot(
            for: ThrowCoreFixture.datelineMapQuery(longitude: 179.8),
        )

        let duplicateID = try #require(
            AircraftID(kind: .providerMarkedNonICAO, rawValue: "duplicate"),
        )
        let duplicate = try #require(snapshot.observations.first { $0.id == duplicateID })
        let route = try #require(snapshot.routeResultsByAircraft[duplicateID]?.route)
        #expect(await transport.recordedRequests().count == 2)
        #expect(snapshot.observations.count == 3)
        #expect(duplicate.coordinate.latitude == 0.1)
        #expect(route.origin.rawValue == "SFO")
        #expect(route.destination.rawValue == "NRT")
        #expect(snapshot.successfulHTTPStatus == 200)
    }

    @Test func antimeridianFailureNeverReturnsTheSuccessfulHalf() async throws {
        let data = Data(
            #"{"data":[{"fr24_id":"partial","lat":0.0,"lon":179.9}]}"#.utf8,
        )
        let transport = ScriptedHTTPTransport(outcomes: [
            .response(ThrowCoreFixture.response(data: data)),
            .failure(HTTPTransportFailure(category: .timedOut)),
        ])
        let source = try makeSource(token: "token", transport: transport)

        await #expect(throws: AircraftSourceFailure.transport(.timedOut)) {
            try await source.snapshot(
                for: ThrowCoreFixture.datelineMapQuery(longitude: 179.8),
            )
        }
        #expect(await transport.recordedRequests().count == 2)
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

    @Test func duplicateProviderRowsKeepTheFreshestMatchingRoute() throws {
        let data = Data(
            """
            {"data":[
              {"fr24_id":"same-leg","lat":37.01,"lon":-122.0,
               "timestamp":"2023-11-14T22:13:20Z","orig_iata":"SFO","dest_iata":"MEX"},
              {"fr24_id":"same-leg","lat":38.01,"lon":-121.0,
               "timestamp":"2023-11-14T21:13:20Z","orig_iata":"DEL","dest_iata":"EWR"}
            ]}
            """.utf8,
        )

        let snapshot = try Flightradar24Decoder().decode(
            data,
            fetchedAt: ThrowCoreFixture.date,
        )
        let observation = try #require(snapshot.observations.first)
        let route = try #require(snapshot.routeResultsByAircraft[observation.id]?.route)

        #expect(snapshot.observations.count == 1)
        #expect(observation.coordinate.latitude == 37.01)
        #expect(route.origin.rawValue == "SFO")
        #expect(route.destination.rawValue == "MEX")
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
        try makeSource(
            token: token,
            transport: ScriptedHTTPTransport(outcomes: outcomes),
        )
    }

    private func makeSource(
        token: String,
        transport: ScriptedHTTPTransport,
    ) throws -> Flightradar24Source {
        try Flightradar24Source(
            transport: transport,
            decoder: Flightradar24Decoder(),
            credential: AircraftCredential(secret: token),
            dateProvider: FixedDateProvider(date: ThrowCoreFixture.date),
        )
    }
}
