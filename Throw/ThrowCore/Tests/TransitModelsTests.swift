import Testing
@testable import ThrowCore

struct TransitModelsTests {
    @Test func identitiesRejectEmptyValuesAndNormalizeDirectionalStops() throws {
        #expect(TransitRouteID(agencyID: TransitFixture.agencyID, rawValue: " ") == nil)
        let northbound = try TransitFixture.stopID("A01N")
        #expect(northbound.parentStationID.rawValue == "A01")
    }

    @Test func colorsRoundTripCanonicalHex() throws {
        #expect(try TransitFixture.color().hex == "0039A6")
    }

    @Test func transitViewportDefaultsToFiveNauticalMiles() {
        #expect(TransitMapViewport.defaultValue.radius.value == 5)
    }

    @Test(arguments: [2.0, 3.0, 5.0, 8.0])
    func transitViewportAcceptsWholeNauticalMilesInNeighborhoodRange(radius: Double) throws {
        #expect(
            try TransitMapViewport(radius: NauticalMiles(value: radius)).radius.value == radius,
        )
    }

    @Test(arguments: [0.0, 1.0, 2.5, 8.5, 9.0, 50.0, 240.0])
    func transitViewportRejectsUnsupportedRadii(radius: Double) throws {
        #expect(throws: ThrowValidationError.invalidPreferencePayload) {
            try TransitMapViewport(radius: NauticalMiles(value: radius))
        }
    }
}
