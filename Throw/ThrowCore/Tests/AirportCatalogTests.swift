import Testing
@testable import ThrowCore

struct AirportCatalogTests {
    @Test func aliasesResolveToTheSameAirport() throws {
        let airport = try fixtureAirport(id: 1, latitude: 37, longitude: -122)
        let catalog = AirportCatalog(airports: [airport])
        let observer = try ThrowCoreFixture.observer()

        #expect(try catalog.airport(for: #require(AirportCode(rawValue: "SFO")), near: observer)?
            .id == airport.id)
        #expect(try catalog.airport(for: #require(AirportCode(rawValue: "KSFO")), near: observer)?
            .id == airport.id)
    }

    @Test func spatialLookupCrossesTheDateLine() throws {
        let airport = try fixtureAirport(id: 2, latitude: 0, longitude: 179.9)
        let catalog = AirportCatalog(airports: [airport])
        let results = try catalog.airports(
            within: NauticalMiles(value: 20),
            of: GeoCoordinate(latitude: 0, longitude: -179.9),
        )
        #expect(results.map(\.id) == [airport.id])
    }

    private func fixtureAirport(
        id: Int,
        latitude: Double,
        longitude: Double,
    ) throws -> AirportRecord {
        try AirportRecord(
            id: AirportID(rawValue: id),
            coordinate: GeoCoordinate(latitude: latitude, longitude: longitude),
            elevation: Altitude(feet: 10),
            codes: [
                #require(AirportCode(rawValue: "SFO")),
                #require(AirportCode(rawValue: "KSFO")),
            ],
            runways: [],
        )
    }
}
