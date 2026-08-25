import Foundation
import Testing
@testable import ThrowCore

struct FlightRouteModelsTests {
    @Test(arguments: [" ual123 ", "ANZ4", "N123TH"])
    func callsignsNormalizeValidBroadcastValues(_ value: String) throws {
        let callsign = try #require(FlightCallsign(rawValue: value))
        #expect(callsign.rawValue == value.trimmingCharacters(in: .whitespaces).uppercased())
    }

    @Test(arguments: ["", "A", "CALL-SIGN", "TOO_LONG_CALLSIGN"])
    func callsignsRejectValuesUnsuitableForRouteLookup(_ value: String) {
        #expect(FlightCallsign(rawValue: value) == nil)
    }

    @Test func descriptionsRedactCallsignsRoutesAndCoordinates() throws {
        let callsignSentinel = "UAL123"
        let coordinateSentinel = "37.123456"
        let callsign = try #require(FlightCallsign(rawValue: callsignSentinel))
        let origin = try #require(AirportCode(rawValue: "JFK"))
        let destination = try #require(AirportCode(rawValue: "SFO"))
        let values: [Any] = try [
            callsign,
            origin,
            FlightRoute(origin: origin, destination: destination),
            FlightRouteQuery(
                callsign: callsign,
                coordinate: GeoCoordinate(
                    latitude: 37.123456,
                    longitude: -122,
                ),
            ),
        ]
        for value in values {
            let descriptions = [String(describing: value), String(reflecting: value)]
            for description in descriptions {
                #expect(description.contains(callsignSentinel) == false)
                #expect(description.contains(coordinateSentinel) == false)
                #expect(description.contains("JFK") == false)
                #expect(description.contains("SFO") == false)
            }
        }
    }
}
