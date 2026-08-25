import Testing
@testable import ThrowCore

struct FlightActivityClassifierTests {
    @Test func localDestinationConfirmsApproach() throws {
        let airport = try fixtureAirport()
        let classifier =
            FlightActivityClassifier(airportCatalog: AirportCatalog(airports: [airport]))
        let observation = try ThrowCoreFixture.observation(
            latitude: 37,
            longitude: -122.1,
            altitudeFeet: 4000,
            groundTrackDegrees: 90,
            verticalRateFeetPerMinute: -200,
        )
        let route = try FlightRoute(
            origin: #require(AirportCode(rawValue: "LAX")),
            destination: #require(AirportCode(rawValue: "SFO")),
        )

        guard case let .arrival(context, stage, certainty) = try classifier.activity(
            for: observation,
            observer: ThrowCoreFixture.observer(),
            route: route,
        ) else {
            Issue.record("Expected an arrival estimate")
            return
        }
        #expect(context.airport.id == airport.id)
        #expect(stage == .approach)
        #expect(certainty == .confirmed)
    }

    @Test func geometryInfersArrivalOnlyWithAltitudeVerticalRateAndAlignment() throws {
        let airport = try fixtureAirport()
        let classifier =
            FlightActivityClassifier(airportCatalog: AirportCatalog(airports: [airport]))
        let observation = try ThrowCoreFixture.observation(
            latitude: 37,
            longitude: -122.1,
            altitudeFeet: 5000,
            groundTrackDegrees: 90,
            verticalRateFeetPerMinute: -300,
        )

        guard case let .arrival(_, stage, certainty) = try classifier.activity(
            for: observation,
            observer: ThrowCoreFixture.observer(),
            route: nil,
        ) else {
            Issue.record("Expected an inferred arrival estimate")
            return
        }
        #expect(stage == .approach)
        #expect(certainty == .inferred)
    }

    @Test func groundAircraftAndMissingMotionStayUncued() throws {
        let airport = try fixtureAirport()
        let classifier =
            FlightActivityClassifier(airportCatalog: AirportCatalog(airports: [airport]))
        let ground = try ThrowCoreFixture.observation(
            state: .ground,
            verticalRateFeetPerMinute: -500,
        )
        let missingVerticalRate = try ThrowCoreFixture.observation(
            latitude: 37,
            longitude: -122.1,
            altitudeFeet: 3000,
            verticalRateFeetPerMinute: nil,
        )
        #expect(try classifier.activity(
            for: ground,
            observer: ThrowCoreFixture.observer(),
            route: nil,
        ) == .overflight)
        #expect(try classifier.activity(
            for: missingVerticalRate,
            observer: ThrowCoreFixture.observer(),
            route: nil,
        ) == .overflight)
    }

    private func fixtureAirport() throws -> AirportRecord {
        try AirportRecord(
            id: AirportID(rawValue: 1),
            coordinate: GeoCoordinate(latitude: 37, longitude: -122),
            elevation: Altitude(feet: 10),
            codes: [
                #require(AirportCode(rawValue: "SFO")),
                #require(AirportCode(rawValue: "KSFO")),
            ],
            runways: [RunwayRecord(
                id: 1,
                lengthFeet: 10000,
                lowEnd: GeoCoordinate(latitude: 37, longitude: -122.1),
                highEnd: GeoCoordinate(latitude: 37, longitude: -121.9),
            )],
        )
    }
}
