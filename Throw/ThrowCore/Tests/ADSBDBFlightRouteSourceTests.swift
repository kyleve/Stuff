import Foundation
import Testing
@testable import ThrowCore

struct ADSBDBFlightRouteSourceTests {
    @Test func requestContainsOnlyTheCallsign() async throws {
        let transport = ScriptedHTTPTransport(outcomes: [
            .response(ThrowCoreFixture.response(data: Self.routeResponse())),
        ])
        let source = ADSBDBFlightRouteSource(transport: transport)
        let callsign = try #require(FlightCallsign(rawValue: "UAL123"))

        _ = try await source.routes(for: [FlightRouteQuery(callsign: callsign)])

        let request = try #require(await transport.recordedRequests().first)
        #expect(request.method == .get)
        #expect(request.url.absoluteString == "https://api.adsbdb.com/v0/callsign/UAL123")
        #expect(request.headers == [.accept: "application/json"])
    }

    @Test func routeResponsePrefersIATAAndFallsBackToICAO() async throws {
        let source = ADSBDBFlightRouteSource(
            transport: ScriptedHTTPTransport(outcomes: [
                .response(ThrowCoreFixture.response(data: Self.routeResponse())),
            ]),
        )
        let callsign = try #require(FlightCallsign(rawValue: "UAL123"))

        let routes = try await source.routes(for: [FlightRouteQuery(callsign: callsign)])

        #expect(routes[callsign]?.origin.rawValue == "JFK")
        #expect(routes[callsign]?.destination.rawValue == "KSFO")
    }

    @Test func unknownCallsignIsAValidEmptyResult() async throws {
        let source = ADSBDBFlightRouteSource(
            transport: ScriptedHTTPTransport(outcomes: [
                .response(HTTPResponse(statusCode: 404, headers: [:], data: Data())),
            ]),
        )
        let callsign = try #require(FlightCallsign(rawValue: "UNKNOWN1"))

        let routes = try await source.routes(for: [FlightRouteQuery(callsign: callsign)])

        #expect(routes.isEmpty)
    }

    @Test func responseBodiesStayOutOfRouteErrors() async throws {
        let sentinel = "route-response-DO-NOT-LEAK"
        let source = ADSBDBFlightRouteSource(
            transport: ScriptedHTTPTransport(outcomes: [
                .response(ThrowCoreFixture.response(data: Data(sentinel.utf8))),
            ]),
        )
        let callsign = try #require(FlightCallsign(rawValue: "UAL123"))

        do {
            _ = try await source.routes(for: [FlightRouteQuery(callsign: callsign)])
            Issue.record("Expected malformed route data to fail.")
        } catch {
            #expect(String(describing: error).contains(sentinel) == false)
            #expect(String(reflecting: error).contains(sentinel) == false)
        }
    }

    private static func routeResponse() -> Data {
        Data(
            """
            {
              "response": {
                "flightroute": {
                  "origin": {"iata_code": "JFK", "icao_code": "KJFK"},
                  "destination": {"iata_code": "", "icao_code": "KSFO"}
                }
              }
            }
            """.utf8,
        )
    }
}
