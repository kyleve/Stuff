import Foundation

public struct AircraftID: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public enum Kind: String, Hashable, Sendable {
        case icao
        case providerMarkedNonICAO = "non-icao"
    }

    public let kind: Kind
    public let rawValue: String

    public init?(kind: Kind, rawValue: String) {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.isEmpty == false else { return nil }
        self.kind = kind
        self.rawValue = normalized
    }

    public var layerMarkID: LayerMarkID {
        .aircraft(self)
    }

    public var description: String {
        "<AircraftID redacted>"
    }

    public var debugDescription: String {
        description
    }
}

public enum AircraftSourceKind: String, CaseIterable, Codable, Hashable, Sendable {
    case adsbLol = "adsb-lol"
    case readsb
    case adsbExchangeRapidAPI = "adsb-exchange-rapidapi"
    case flightradar24
}

public enum AircraftCredentialID: String, Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    case rapidAPI = "rapidapi-personal-key"
    case flightradar24 = "flightradar24-api-token"

    public var description: String {
        "<AircraftCredentialID redacted>"
    }

    public var debugDescription: String {
        description
    }
}

public struct ReadsbConfiguration: Equatable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let aircraftJSONURL: URL

    public init(aircraftJSONURL: URL) throws {
        self.aircraftJSONURL = try ReadsbURLValidator.validate(aircraftJSONURL)
    }

    public var description: String {
        "<ReadsbConfiguration url=<redacted>>"
    }

    public var debugDescription: String {
        description
    }
}

public struct ADSBExchangeConfiguration: Equatable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let pollingInterval: PollingInterval

    public init(pollingInterval: PollingInterval) {
        self.pollingInterval = pollingInterval
    }

    public var description: String {
        "<ADSBExchangeConfiguration credential=<redacted>>"
    }

    public var debugDescription: String {
        description
    }
}

public struct Flightradar24Configuration: Equatable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let pollingInterval: PollingInterval

    public init(pollingInterval: PollingInterval) {
        self.pollingInterval = pollingInterval
    }

    public var description: String {
        "<Flightradar24Configuration credential=<redacted>>"
    }

    public var debugDescription: String {
        description
    }
}

public enum AircraftSourceConfiguration: Equatable, Sendable {
    case adsbLol
    case readsb(ReadsbConfiguration)
    case adsbExchangeRapidAPI(ADSBExchangeConfiguration)
    case flightradar24(Flightradar24Configuration)

    public var kind: AircraftSourceKind {
        switch self {
            case .adsbLol: .adsbLol
            case .readsb: .readsb
            case .adsbExchangeRapidAPI: .adsbExchangeRapidAPI
            case .flightradar24: .flightradar24
        }
    }

    public var basePollingInterval: Duration {
        switch self {
            case .adsbLol:
                .seconds(10)
            case .readsb:
                .seconds(1)
            case let .adsbExchangeRapidAPI(configuration):
                configuration.pollingInterval.duration
            case let .flightradar24(configuration):
                configuration.pollingInterval.duration
        }
    }
}

extension AircraftSourceConfiguration: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        "<AircraftSourceConfiguration kind=\(kind.rawValue)>"
    }

    public var debugDescription: String {
        description
    }
}

public struct AircraftQuery: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let observer: ObserverPosition
    /// The center of the requested region. It equals the observer in True Sky
    /// and may be a fixed regional Map center in Map mode.
    public let center: GeoCoordinate
    public let viewport: ProjectionViewport
    public let includeGroundAircraft: Bool

    public init(
        observer: ObserverPosition,
        center: GeoCoordinate,
        viewport: ProjectionViewport,
        includeGroundAircraft: Bool,
    ) {
        self.observer = observer
        self.center = center
        self.viewport = viewport
        self.includeGroundAircraft = includeGroundAircraft
    }

    public var description: String {
        "<AircraftQuery observer=<redacted>>"
    }

    public var debugDescription: String {
        description
    }
}

public enum AircraftAirborneState: String, Hashable, Sendable {
    case airborne
    case ground
    case unknown
}

/// A normalized ICAO aircraft type designator supplied by an observation provider.
public struct AircraftTypeDesignator: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init?(rawValue: String) {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard (2 ... 4).contains(normalized.count),
              normalized.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) })
        else { return nil }
        self.rawValue = normalized
    }

    public var description: String {
        rawValue
    }
}

/// A normalized three-character ICAO airline designator supplied by a provider.
public struct AirlineICAODesignator: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init?(rawValue: String) {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalized.count == 3,
              normalized.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) })
        else { return nil }
        self.rawValue = normalized
    }

    public var description: String {
        rawValue
    }
}

/// The semantic ADS-B emitter category used as a classification hint.
public enum AircraftEmitterCategory: String, Hashable, Sendable {
    case noInformation = "A0"
    case light = "A1"
    case small = "A2"
    case large = "A3"
    case highVortexLarge = "A4"
    case heavy = "A5"
    case highPerformance = "A6"
    case rotorcraft = "A7"
    case glider = "B1"
    case lighterThanAir = "B2"
    case parachutist = "B3"
    case ultralight = "B4"
    case unmanned = "B6"
    case spaceVehicle = "B7"
    case emergencySurface = "C1"
    case serviceSurface = "C2"
    case pointObstacle = "C3"

    public init?(providerValue: String) {
        self
            .init(rawValue: providerValue.trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased())
    }
}

public struct AircraftObservationMetadata: Hashable, Sendable {
    public let source: AircraftSourceKind
    public let positionSource: String?
    public let messageCount: Int?

    public init(source: AircraftSourceKind, positionSource: String?, messageCount: Int?) {
        self.source = source
        self.positionSource = positionSource
        self.messageCount = messageCount
    }
}

public struct AircraftObservation: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let id: AircraftID
    public let coordinate: GeoCoordinate
    public let geometricAltitude: Altitude?
    public let barometricAltitude: Altitude?
    public let airborneState: AircraftAirborneState
    public let groundTrack: Bearing?
    public let trueHeading: Bearing?
    public let magneticHeading: Bearing?
    public let groundSpeedKnots: Double?
    public let verticalRateFeetPerMinute: Double?
    public let callsign: String?
    public let registration: String?
    public let aircraftType: AircraftTypeDesignator?
    public let emitterCategory: AircraftEmitterCategory?
    public let airlineDesignator: AirlineICAODesignator?
    public let messageObservedAt: Date
    public let positionObservedAt: Date
    public let fetchedAt: Date
    public let metadata: AircraftObservationMetadata

    public init(
        id: AircraftID,
        coordinate: GeoCoordinate,
        geometricAltitude: Altitude?,
        barometricAltitude: Altitude?,
        airborneState: AircraftAirborneState,
        groundTrack: Bearing?,
        trueHeading: Bearing?,
        magneticHeading: Bearing?,
        groundSpeedKnots: Double?,
        verticalRateFeetPerMinute: Double?,
        callsign: String?,
        registration: String?,
        aircraftType: AircraftTypeDesignator?,
        emitterCategory: AircraftEmitterCategory?,
        airlineDesignator: AirlineICAODesignator?,
        messageObservedAt: Date,
        positionObservedAt: Date,
        fetchedAt: Date,
        metadata: AircraftObservationMetadata,
    ) throws {
        if let groundSpeedKnots {
            guard groundSpeedKnots.isFinite, (0 ... 2000).contains(groundSpeedKnots) else {
                throw ThrowValidationError.outOfRange(
                    field: "groundSpeed",
                    closedRange: 0 ... 2000,
                )
            }
        }
        if let verticalRateFeetPerMinute {
            guard verticalRateFeetPerMinute.isFinite else {
                throw ThrowValidationError.nonFiniteValue(field: "verticalRate")
            }
        }
        self.id = id
        self.coordinate = coordinate
        self.geometricAltitude = geometricAltitude
        self.barometricAltitude = barometricAltitude
        self.airborneState = airborneState
        self.groundTrack = groundTrack
        self.trueHeading = trueHeading
        self.magneticHeading = magneticHeading
        self.groundSpeedKnots = groundSpeedKnots
        self.verticalRateFeetPerMinute = verticalRateFeetPerMinute
        self.callsign = callsign?.nilIfTrimmedEmpty
        self.registration = registration?.nilIfTrimmedEmpty
        self.aircraftType = aircraftType
        self.emitterCategory = emitterCategory
        self.airlineDesignator = airlineDesignator
        self.messageObservedAt = messageObservedAt
        self.positionObservedAt = positionObservedAt
        self.fetchedAt = fetchedAt
        self.metadata = metadata
    }

    public var preferredSkyAltitude: Altitude? {
        skyAltitude.value
    }

    public var skyAltitude: GeodeticAltitude {
        if let geometricAltitude {
            return .available(geometricAltitude, quality: .geometric)
        }
        if let barometricAltitude {
            return .available(barometricAltitude, quality: .barometricApproximation)
        }
        return .unavailable
    }

    public var description: String {
        "<AircraftObservation redacted>"
    }

    public var debugDescription: String {
        description
    }
}

public struct AircraftSnapshot: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let source: AircraftSourceKind
    public let fetchedAt: Date
    public let observations: [AircraftObservation]
    /// Completed route results supplied with the matching source observation.
    /// Absence means that the source did not resolve route availability.
    public let routeResultsByAircraft: [AircraftID: FlightRouteResult]
    public let successfulHTTPStatus: Int?

    public init(
        source: AircraftSourceKind,
        fetchedAt: Date,
        observations: [AircraftObservation],
    ) {
        self.init(
            source: source,
            fetchedAt: fetchedAt,
            observations: observations,
            routeResultsByAircraft: [:],
            successfulHTTPStatus: nil,
        )
    }

    public init(
        source: AircraftSourceKind,
        fetchedAt: Date,
        observations: [AircraftObservation],
        successfulHTTPStatus: Int?,
    ) {
        self.init(
            source: source,
            fetchedAt: fetchedAt,
            observations: observations,
            routeResultsByAircraft: [:],
            successfulHTTPStatus: successfulHTTPStatus,
        )
    }

    public init(
        source: AircraftSourceKind,
        fetchedAt: Date,
        observations: [AircraftObservation],
        routeResultsByAircraft: [AircraftID: FlightRouteResult],
        successfulHTTPStatus: Int?,
    ) {
        let observations = Self.canonicalObservations(observations)
        precondition(observations.allSatisfy { $0.metadata.source == source })
        let observationIDs = Set(observations.map(\.id))
        precondition(routeResultsByAircraft.keys.allSatisfy(observationIDs.contains))
        precondition(
            successfulHTTPStatus.map { (200 ..< 300).contains($0) } ?? true,
            "A successful snapshot can only carry a successful HTTP status",
        )
        self.source = source
        self.fetchedAt = fetchedAt
        self.observations = observations
        self.routeResultsByAircraft = routeResultsByAircraft
        self.successfulHTTPStatus = successfulHTTPStatus
    }

    /// Selects the freshest position while retaining the first-seen order of identities.
    static func canonicalObservations(
        _ observations: [AircraftObservation],
    ) -> [AircraftObservation] {
        var result: [AircraftObservation] = []
        result.reserveCapacity(observations.count)
        var indexByID: [AircraftID: Int] = [:]
        indexByID.reserveCapacity(observations.count)

        for observation in observations {
            if let index = indexByID[observation.id] {
                if prefers(observation, over: result[index]) {
                    result[index] = observation
                }
            } else {
                indexByID[observation.id] = result.count
                result.append(observation)
            }
        }
        return result
    }

    /// Applies the tie-break order shared by snapshot and route-envelope normalization.
    static func prefers(
        _ candidate: AircraftObservation,
        over existing: AircraftObservation,
    ) -> Bool {
        if candidate.positionObservedAt != existing.positionObservedAt {
            return candidate.positionObservedAt > existing.positionObservedAt
        }
        if candidate.messageObservedAt != existing.messageObservedAt {
            return candidate.messageObservedAt > existing.messageObservedAt
        }
        if candidate.fetchedAt != existing.fetchedAt {
            return candidate.fetchedAt > existing.fetchedAt
        }
        return true
    }

    public var description: String {
        "<AircraftSnapshot source=\(source.rawValue) count=\(observations.count)>"
    }

    public var debugDescription: String {
        description
    }
}

public enum AircraftTransportErrorCategory: String, Equatable, Sendable {
    case cancelled
    case timedOut
    case offline
    case localNetworkDenied
    case connection
    case invalidResponse
    case other
}

public enum AircraftSourceFailure: Error, Equatable, Sendable {
    case invalidConfiguration
    case missingCredential
    case invalidCredential
    case subscriptionRequired
    case entitlementRejected
    case quotaReached(retryAfterSeconds: Double?)
    case provider(statusCode: Int, retryAfterSeconds: Double?)
    case transport(AircraftTransportErrorCategory)
    case decoding

    public var retryAfterSeconds: Double? {
        switch self {
            case let .quotaReached(retryAfterSeconds),
                 let .provider(_, retryAfterSeconds):
                retryAfterSeconds
            case .invalidConfiguration,
                 .missingCredential,
                 .invalidCredential,
                 .subscriptionRequired,
                 .entitlementRejected,
                 .transport,
                 .decoding:
                nil
        }
    }

    public var isRetryable: Bool {
        switch self {
            case .quotaReached, .transport, .decoding:
                true
            case let .provider(statusCode, _):
                (500 ... 599).contains(statusCode)
            case .invalidConfiguration,
                 .missingCredential,
                 .invalidCredential,
                 .subscriptionRequired,
                 .entitlementRejected:
                false
        }
    }
}

public protocol AircraftObservationSource: Sendable {
    func snapshot(for query: AircraftQuery) async throws -> AircraftSnapshot
}

extension String {
    fileprivate var nilIfTrimmedEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
