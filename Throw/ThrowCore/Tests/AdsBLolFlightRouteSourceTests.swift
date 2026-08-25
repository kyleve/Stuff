import Foundation
import Testing
@testable import ThrowCore

struct AdsBLolFlightRouteSourceTests {
    @Test func batchRequestCarriesCallsignAndAircraftPositionInJSONBody() async throws {
        let transport = ScriptedHTTPTransport(outcomes: [
            .response(ThrowCoreFixture.response(data: Data("[]".utf8))),
        ])
        let source = AdsBLolFlightRouteSource(transport: transport)
        let callsign = try #require(FlightCallsign(rawValue: "UAL123"))
        let coordinate = try GeoCoordinate(latitude: 37.25, longitude: -122.5)

        _ = try await source.routes(
            for: [FlightRouteQuery(callsign: callsign, coordinate: coordinate)],
        )

        let request = try #require(await transport.recordedRequests().first)
        #expect(request.method == .post)
        #expect(request.url == AdsBLolFlightRouteSource.endpoint)
        #expect(request.headers[.contentType] == "application/json")
        let body = try #require(request.body)
        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let planes = try #require(object["planes"] as? [[String: Any]])
        let plane = try #require(planes.first)
        #expect(plane["callsign"] as? String == "UAL123")
        #expect(plane["lat"] as? Double == 37.25)
        #expect(plane["lng"] as? Double == -122.5)
    }

    @Test func routeResponsePrefersIATAAndFallsBackToICAO() async throws {
        let data = Data(
            """
            [{
              "callsign": "UAL123",
              "_airports": [
                {"iata": "JFK", "icao": "KJFK"},
                {"iata": "", "icao": "KSFO"}
              ]
            }]
            """.utf8,
        )
        let source = AdsBLolFlightRouteSource(
            transport: ScriptedHTTPTransport(outcomes: [
                .response(ThrowCoreFixture.response(data: data)),
            ]),
        )
        let callsign = try #require(FlightCallsign(rawValue: "UAL123"))

        let routes = try await source.routes(for: [
            FlightRouteQuery(
                callsign: callsign,
                coordinate: GeoCoordinate(latitude: 37, longitude: -122),
            ),
        ])

        #expect(routes[callsign]?.origin.rawValue == "JFK")
        #expect(routes[callsign]?.destination.rawValue == "KSFO")
    }

    @Test func responseBodiesStayOutOfRouteErrors() async throws {
        let sentinel = "route-response-DO-NOT-LEAK"
        let source = AdsBLolFlightRouteSource(
            transport: ScriptedHTTPTransport(outcomes: [
                .response(ThrowCoreFixture.response(data: Data(sentinel.utf8))),
            ]),
        )
        let callsign = try #require(FlightCallsign(rawValue: "UAL123"))

        do {
            _ = try await source.routes(for: [
                FlightRouteQuery(
                    callsign: callsign,
                    coordinate: GeoCoordinate(latitude: 37, longitude: -122),
                ),
            ])
            Issue.record("Expected malformed route data to fail.")
        } catch {
            #expect(String(describing: error).contains(sentinel) == false)
            #expect(String(reflecting: error).contains(sentinel) == false)
        }
    }
}
