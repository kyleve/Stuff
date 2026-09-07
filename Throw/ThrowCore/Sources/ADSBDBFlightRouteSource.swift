import Foundation

/// Callsign-only route enrichment through ADSBDB's public API.
public struct ADSBDBFlightRouteSource: FlightRouteSource {
    public static let endpoint = URL(string: "https://api.adsbdb.com/v0/callsign/")!
    public static let maximumConcurrentRequests = 4

    private let transport: any HTTPTransport

    public init(transport: any HTTPTransport) {
        self.transport = transport
    }

    public func routes(
        for queries: [FlightRouteQuery],
    ) async throws -> [FlightCallsign: FlightRoute] {
        guard queries.isEmpty == false else { return [:] }
        var remaining = queries.makeIterator()

        return try await withThrowingTaskGroup(
            of: LookupResult.self,
            returning: [FlightCallsign: FlightRoute].self,
        ) { group in
            for _ in 0 ..< min(Self.maximumConcurrentRequests, queries.count) {
                guard let query = remaining.next() else { break }
                group.addTask {
                    try await lookup(query)
                }
            }

            var routes: [FlightCallsign: FlightRoute] = [:]
            while let result = try await group.next() {
                if let route = result.route {
                    routes[result.callsign] = route
                }
                if let query = remaining.next() {
                    group.addTask {
                        try await lookup(query)
                    }
                }
            }
            return routes
        }
    }

    public func makeRequest(for query: FlightRouteQuery) -> HTTPRequest {
        HTTPRequest(
            method: .get,
            url: Self.endpoint.appendingPathComponent(query.callsign.rawValue),
            headers: [.accept: "application/json"],
            timeoutSeconds: 8,
        )
    }

    private func lookup(_ query: FlightRouteQuery) async throws -> LookupResult {
        do {
            let response = try await transport.response(for: makeRequest(for: query))
            if response.statusCode == 404 {
                return LookupResult(callsign: query.callsign, route: nil)
            }
            guard (200 ... 299).contains(response.statusCode) else {
                throw FlightRouteLookupError.provider
            }
            return try LookupResult(
                callsign: query.callsign,
                route: Self.decode(response.data),
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as FlightRouteLookupError {
            throw error
        } catch let error as HTTPTransportFailure {
            throw FlightRouteLookupError.transport(error.category)
        } catch {
            throw FlightRouteLookupError.decoding
        }
    }

    private static func decode(_ data: Data) throws -> FlightRoute {
        let record: ADSBDBResponse.RouteRecord
        do {
            record = try JSONDecoder().decode(ADSBDBResponse.self, from: data)
                .response.flightroute
        } catch {
            throw FlightRouteLookupError.decoding
        }
        guard let origin = record.origin.preferredCode,
              let destination = record.destination.preferredCode,
              origin != destination
        else {
            throw FlightRouteLookupError.decoding
        }
        return FlightRoute(origin: origin, destination: destination)
    }
}

private struct LookupResult {
    let callsign: FlightCallsign
    let route: FlightRoute?
}

private struct ADSBDBResponse: Decodable {
    struct Payload: Decodable {
        let flightroute: RouteRecord
    }

    struct RouteRecord: Decodable {
        let origin: Airport
        let destination: Airport
    }

    struct Airport: Decodable {
        let iataCode: String?
        let icaoCode: String?

        var preferredCode: AirportCode? {
            iataCode.flatMap(AirportCode.init(rawValue:))
                ?? icaoCode.flatMap(AirportCode.init(rawValue:))
        }

        enum CodingKeys: String, CodingKey {
            case iataCode = "iata_code"
            case icaoCode = "icao_code"
        }
    }

    let response: Payload
}
