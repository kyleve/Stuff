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

    public init(kind: Kind, rawValue: String) {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        precondition(normalized.isEmpty == false, "An aircraft ID must not be empty")
        self.kind = kind
        self.rawValue = normalized
    }

    public var layerMarkID: LayerMarkID {
        LayerMarkID(
            layerID: .flights,
            namespace: .aircraft,
            rawValue: "\(kind.rawValue)/\(rawValue)",
        )
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
}

public struct AircraftCredentialID: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public static let rapidAPI = AircraftCredentialID(rawValue: "rapidapi-personal-key")

    public let rawValue: String

    public init(rawValue: String) {
        precondition(rawValue.isEmpty == false, "A credential ID must not be empty")
        self.rawValue = rawValue
    }

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
    public let credentialID: AircraftCredentialID

    public init(pollingInterval: PollingInterval, credentialID: AircraftCredentialID) {
        self.pollingInterval = pollingInterval
        self.credentialID = credentialID
    }

    public var description: String {
        "<ADSBExchangeConfiguration credential=<redacted>>"
    }

    public var debugDescription: String {
        description
    }
}

public enum AircraftSourceConfiguration: Equatable, Sendable {
    case adsbLol
    case readsb(ReadsbConfiguration)
    case adsbExchangeRapidAPI(ADSBExchangeConfiguration)

    public var kind: AircraftSourceKind {
        switch self {
            case .adsbLol: .adsbLol
            case .readsb: .readsb
            case .adsbExchangeRapidAPI: .adsbExchangeRapidAPI
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
    public let viewport: ProjectionViewport
    public let includeGroundAircraft: Bool

    public init(
        observer: ObserverPosition,
        viewport: ProjectionViewport,
        includeGroundAircraft: Bool,
    ) {
        self.observer = observer
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
        self.messageObservedAt = messageObservedAt
        self.positionObservedAt = positionObservedAt
        self.fetchedAt = fetchedAt
        self.metadata = metadata
    }

    public var preferredSkyAltitude: Altitude? {
        geometricAltitude ?? barometricAltitude
    }

    public var skyAltitudeQuality: AltitudeQuality {
        if geometricAltitude != nil { return .geometric }
        if barometricAltitude != nil { return .barometricApproximation }
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
            successfulHTTPStatus: nil,
        )
    }

    public init(
        source: AircraftSourceKind,
        fetchedAt: Date,
        observations: [AircraftObservation],
        successfulHTTPStatus: Int?,
    ) {
        precondition(observations.allSatisfy { $0.metadata.source == source })
        precondition(
            successfulHTTPStatus.map { (200 ..< 300).contains($0) } ?? true,
            "A successful snapshot can only carry a successful HTTP status",
        )
        self.source = source
        self.fetchedAt = fetchedAt
        self.observations = observations
        self.successfulHTTPStatus = successfulHTTPStatus
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
