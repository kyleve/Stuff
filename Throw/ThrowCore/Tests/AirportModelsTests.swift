import Testing
@testable import ThrowCore

struct AirportModelsTests {
    @Test func longestOpenRunwayUsesLength() throws {
        let airport = try airport(runwayLengths: [2000, 7500, 4000])
        #expect(airport.longestOpenRunway?.lengthFeet == 7500)
        #expect(airport.displayCode.rawValue == "SFO")
    }

    private func airport(runwayLengths: [Int]) throws -> AirportRecord {
        let low = try GeoCoordinate(latitude: 37, longitude: -122.1)
        let high = try GeoCoordinate(latitude: 37, longitude: -121.9)
        return try AirportRecord(
            id: AirportID(rawValue: 1),
            coordinate: GeoCoordinate(latitude: 37, longitude: -122),
            elevation: Altitude(feet: 10),
            codes: [
                #require(AirportCode(rawValue: "KSFO")),
                #require(AirportCode(rawValue: "SFO")),
            ],
            runways: runwayLengths.enumerated().map { offset, length in
                RunwayRecord(id: offset + 1, lengthFeet: length, lowEnd: low, highEnd: high)
            },
        )
    }
}
