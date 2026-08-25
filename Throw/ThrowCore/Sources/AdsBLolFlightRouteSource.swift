import Foundation

/// Batch route enrichment through adsb.lol's route-set endpoint.
public struct AdsBLolFlightRouteSource: FlightRouteSource {
    public static let endpoint = URL(string: "https://api.adsb.lol/api/0/routeset")!
    public static let maximumBatchSize = 100

    private let transport: any HTTPTransport

    public init(transport: any HTTPTransport) {
        self.transport = transport
    }

    public func routes(
        for queries: [FlightRouteQuery],
    ) async throws -> [FlightCallsign: FlightRoute] {
        guard queries.isEmpty == false else { return [:] }
        let request = try makeRequest(for: Array(queries.prefix(Self.maximumBatchSize)))
        do {
            let response = try await transport.response(for: request)
            guard (200 ... 299).contains(response.statusCode) else {
                throw FlightRouteLookupError.provider
            }
            return try Self.decode(response.data)
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

    public func makeRequest(for queries: [FlightRouteQuery]) throws -> HTTPRequest {
        let payload = RouteRequest(
            planes: Array(queries.prefix(Self.maximumBatchSize)).map {
                RouteRequest.Plane(
                    callsign: $0.callsign.rawValue,
                    lat: $0.coordinate.latitude,
                    lng: $0.coordinate.longitude,
                )
            },
        )
        let body: Data
        do {
            body = try JSONEncoder().encode(payload)
        } catch {
            throw FlightRouteLookupError.decoding
        }
        return HTTPRequest(
            method: .post,
            url: Self.endpoint,
            headers: [
                .accept: "application/json",
                .contentType: "application/json",
            ],
            body: body,
            timeoutSeconds: 8,
        )
    }

    private static func decode(_ data: Data) throws -> [FlightCallsign: FlightRoute] {
        let records: [RouteResponse]
        do {
            records = try JSONDecoder().decode([RouteResponse].self, from: data)
        } catch {
            throw FlightRouteLookupError.decoding
        }
        return records.reduce(into: [:]) { routes, record in
            guard let callsign = FlightCallsign(rawValue: record.callsign),
                  let airports = record.airports,
                  let first = airports.first,
                  let last = airports.last,
                  airports.count >= 2,
                  let origin = first.preferredCode,
                  let destination = last.preferredCode,
                  origin != destination
            else { return }
            routes[callsign] = FlightRoute(origin: origin, destination: destination)
        }
    }
}

private struct RouteRequest: Encodable {
    struct Plane: Encodable {
        let callsign: String
        let lat: Double
        let lng: Double
    }

    let planes: [Plane]
}

private struct RouteResponse: Decodable {
    struct Airport: Decodable {
        let iata: String?
        let icao: String?

        var preferredCode: AirportCode? {
            iata.flatMap(AirportCode.init(rawValue:))
                ?? icao.flatMap(AirportCode.init(rawValue:))
        }
    }

    let airports: [Airport]?
    let callsign: String

    enum CodingKeys: String, CodingKey {
        case airports = "_airports"
        case callsign
    }
}
