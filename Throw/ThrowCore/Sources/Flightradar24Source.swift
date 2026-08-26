import Foundation

public enum Flightradar24DecodingError: Error, Equatable, Sendable {
    case invalidEnvelope
}

/// Reads FR24 live positions and preserves routes from the matching position record.
public struct Flightradar24Decoder: Sendable {
    public init() {}

    public func decode(_ data: Data, fetchedAt: Date) throws -> AircraftSnapshot {
        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            throw Flightradar24DecodingError.invalidEnvelope
        }

        var observations: [AircraftObservation] = []
        var routeResults: [AircraftID: FlightRouteResult] = [:]
        var malformedCount = 0
        observations.reserveCapacity(envelope.data.count)

        for record in envelope.data {
            try Task.checkCancellation()
            do {
                let coordinate = try GeoCoordinate(latitude: record.lat, longitude: record.lon)
                let identity = if let hex = record.hex?.trimmedNonempty {
                    AircraftID(kind: .icao, rawValue: hex)
                } else {
                    AircraftID(kind: .providerMarkedNonICAO, rawValue: record.fr24ID)
                }
                let observedAt = record.timestamp.flatMap(Self.timestamp) ?? fetchedAt
                let observation = try AircraftObservation(
                    id: identity,
                    coordinate: coordinate,
                    geometricAltitude: nil,
                    barometricAltitude: record.alt.map { try Altitude(feet: $0) },
                    airborneState: Self.airborneState(altitudeFeet: record.alt),
                    groundTrack: record.track.map { try Bearing(degrees: $0) },
                    trueHeading: nil,
                    magneticHeading: nil,
                    groundSpeedKnots: record.groundSpeed,
                    verticalRateFeetPerMinute: record.verticalSpeed,
                    callsign: record.flight?.trimmedNonempty ?? record.callsign?.trimmedNonempty,
                    registration: record.registration,
                    aircraftType: record.aircraftType
                        .flatMap(AircraftTypeDesignator.init(rawValue:)),
                    emitterCategory: nil,
                    airlineDesignator: Self.airlineDesignator(record),
                    messageObservedAt: observedAt,
                    positionObservedAt: observedAt,
                    fetchedAt: fetchedAt,
                    metadata: AircraftObservationMetadata(
                        source: .flightradar24,
                        positionSource: record.source,
                        messageCount: nil,
                    ),
                )
                observations.append(observation)
                routeResults[identity] = Self.route(record)
                    .map(FlightRouteResult.route) ?? .unavailable
            } catch {
                malformedCount += 1
            }
        }
        if observations.isEmpty, malformedCount > 0 {
            throw Flightradar24DecodingError.invalidEnvelope
        }
        return AircraftSnapshot(
            source: .flightradar24,
            fetchedAt: fetchedAt,
            observations: observations,
            routeResultsByAircraft: routeResults,
            successfulHTTPStatus: nil,
        )
    }

    private static func airborneState(altitudeFeet: Double?) -> AircraftAirborneState {
        guard let altitudeFeet else { return .unknown }
        return altitudeFeet <= 0 ? .ground : .airborne
    }

    private static func route(_ record: Record) -> FlightRoute? {
        guard let origin = AirportCode(rawValue: record.originIATA?.trimmedNonempty
            ?? record.originICAO?.trimmedNonempty ?? ""),
            let destination = AirportCode(rawValue: record.destinationIATA?.trimmedNonempty
                ?? record.destinationICAO?.trimmedNonempty ?? ""),
            origin != destination
        else { return nil }
        return FlightRoute(origin: origin, destination: destination)
    }

    private static func airlineDesignator(_ record: Record) -> AirlineICAODesignator? {
        for providerValue in [record.paintedAs, record.operatingAs] {
            if let providerValue,
               let designator = AirlineICAODesignator(rawValue: providerValue)
            {
                return designator
            }
        }

        guard let radioCallsign = record.callsign?.trimmedNonempty,
              radioCallsign.count >= 3
        else { return nil }
        return AirlineICAODesignator(rawValue: String(radioCallsign.prefix(3)))
    }

    private static func timestamp(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }
}

/// Keeps FR24 JSON decoding and exact geographic filtering off the polling actor.
actor Flightradar24DecodingWorker {
    private let decoder: Flightradar24Decoder

    init(decoder: Flightradar24Decoder) {
        self.decoder = decoder
    }

    func decode(
        _ data: Data,
        fetchedAt: Date,
        query: AircraftQuery,
    ) throws -> AircraftSnapshot {
        try Task.checkCancellation()
        let decoded = try decoder.decode(data, fetchedAt: fetchedAt)
        try Task.checkCancellation()
        let observations = try CloudAircraftQuery.postFilter(decoded.observations, for: query)
        let includedIDs = Set(observations.map(\.id))
        try Task.checkCancellation()
        return AircraftSnapshot(
            source: .flightradar24,
            fetchedAt: fetchedAt,
            observations: observations,
            routeResultsByAircraft: decoded.routeResultsByAircraft.filter {
                includedIDs.contains($0.key)
            },
            successfulHTTPStatus: nil,
        )
    }
}

public struct Flightradar24Source: AircraftObservationSource, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public static let baseURL = URL(string: "https://fr24api.flightradar24.com/api")!

    private let transport: any HTTPTransport
    private let decodingWorker: Flightradar24DecodingWorker
    private let credential: AircraftCredential
    private let dateProvider: any DateProvider

    public init(
        transport: any HTTPTransport,
        decoder: Flightradar24Decoder,
        credential: AircraftCredential,
        dateProvider: any DateProvider,
    ) {
        self.transport = transport
        decodingWorker = Flightradar24DecodingWorker(decoder: decoder)
        self.credential = credential
        self.dateProvider = dateProvider
    }

    public var description: String {
        "<Flightradar24Source credential=<redacted>>"
    }

    public var debugDescription: String {
        description
    }

    public func snapshot(for query: AircraftQuery) async throws -> AircraftSnapshot {
        try await snapshot(for: query, request: makeRequest(for: query))
    }

    public func credentialTestSnapshot(observer: ObserverPosition) async throws
        -> AircraftSnapshot
    {
        let query = try AircraftQuery(
            observer: observer,
            viewport: .map(MapViewport(radius: NauticalMiles(value: 5))),
            includeGroundAircraft: false,
        )
        return try await snapshot(for: query, request: makeRequest(for: query, radius: 5))
    }

    public func makeRequest(for query: AircraftQuery) throws -> HTTPRequest {
        let plan = try CloudAircraftQuery.plan(for: query)
        return try makeRequest(for: query, radius: plan.transmittedRadius.value)
    }

    private func makeRequest(for query: AircraftQuery, radius: Double) throws -> HTTPRequest {
        let plan = try CloudAircraftQuery.plan(for: query)
        let latitudeSpan = radius / 60
        let cosine = max(0.01, cos(plan.coarseCenter.latitude * .pi / 180))
        let longitudeSpan = min(180, radius / (60 * cosine))
        let north = min(90, plan.coarseCenter.latitude + latitudeSpan)
        let south = max(-90, plan.coarseCenter.latitude - latitudeSpan)
        let west = max(-180, plan.coarseCenter.longitude - longitudeSpan)
        let east = min(180, plan.coarseCenter.longitude + longitudeSpan)
        let bounds = [north, south, west, east]
            .map { String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), $0) }
            .joined(separator: ",")
        var components = URLComponents(
            url: Self.baseURL.appending(path: "live/flight-positions/full"),
            resolvingAgainstBaseURL: false,
        )
        components?.queryItems = [URLQueryItem(name: "bounds", value: bounds)]
        guard let url = components?.url else { throw AircraftSourceFailure.invalidConfiguration }
        return HTTPRequest(
            method: .get,
            url: url,
            headers: [
                .accept: "application/json",
                .acceptVersion: "v1",
                .authorization: "Bearer \(credential.authenticationHeaderValue)",
            ],
            timeoutSeconds: 8,
        )
    }

    private func snapshot(
        for query: AircraftQuery,
        request: HTTPRequest,
    ) async throws -> AircraftSnapshot {
        do {
            let response = try await transport.response(for: request)
            let fetchedAt = dateProvider.now()
            try SourceHTTPValidation.validate(
                response,
                source: .flightradar24,
                receivedAt: fetchedAt,
            )
            let decoded = try await decodingWorker.decode(
                response.data,
                fetchedAt: fetchedAt,
                query: query,
            )
            return AircraftSnapshot(
                source: .flightradar24,
                fetchedAt: fetchedAt,
                observations: decoded.observations,
                routeResultsByAircraft: decoded.routeResultsByAircraft,
                successfulHTTPStatus: response.statusCode,
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as AircraftSourceFailure {
            throw failure
        } catch let failure as HTTPTransportFailure {
            throw AircraftSourceFailure.transport(failure.category)
        } catch {
            throw AircraftSourceFailure.decoding
        }
    }
}

private struct Envelope: Decodable {
    let data: [Record]
}

private struct Record: Decodable {
    let fr24ID: String
    let flight: String?
    let callsign: String?
    let lat: Double
    let lon: Double
    let track: Double?
    let alt: Double?
    let groundSpeed: Double?
    let verticalSpeed: Double?
    let timestamp: String?
    let source: String?
    let hex: String?
    let aircraftType: String?
    let registration: String?
    let paintedAs: String?
    let operatingAs: String?
    let originIATA: String?
    let originICAO: String?
    let destinationIATA: String?
    let destinationICAO: String?

    enum CodingKeys: String, CodingKey {
        case fr24ID = "fr24_id"
        case flight, callsign, lat, lon, track, alt, timestamp, source, hex
        case groundSpeed = "gspeed"
        case verticalSpeed = "vspeed"
        case aircraftType = "type"
        case registration = "reg"
        case paintedAs = "painted_as"
        case operatingAs = "operating_as"
        case originIATA = "orig_iata"
        case originICAO = "orig_icao"
        case destinationIATA = "dest_iata"
        case destinationICAO = "dest_icao"
    }
}

extension String {
    fileprivate var trimmedNonempty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
