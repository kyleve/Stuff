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

    @Test(arguments: [0.0, 7.0, 55.0, 240.0])
    func transitViewportRejectsUnsupportedRadii(radius: Double) throws {
        #expect(throws: ThrowValidationError.invalidPreferencePayload) {
            try TransitMapViewport(radius: NauticalMiles(value: radius))
        }
    }
}
