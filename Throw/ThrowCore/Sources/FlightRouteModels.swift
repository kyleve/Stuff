import Foundation

/// A normalized broadcast callsign used only as the key for route enrichment.
public struct FlightCallsign: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let rawValue: String

    public init?(rawValue: String) {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard (2 ... 12).contains(value.count),
              value.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) })
        else { return nil }
        self.rawValue = value
    }

    public var description: String {
        "<FlightCallsign redacted>"
    }

    public var debugDescription: String {
        description
    }
}

/// An IATA code when available, with ICAO as a fallback for airports without one.
public struct AirportCode: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let rawValue: String

    public init?(rawValue: String) {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard (3 ... 4).contains(value.count),
              value.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) })
        else { return nil }
        self.rawValue = value
    }

    public var description: String {
        "<AirportCode redacted>"
    }

    public var debugDescription: String {
        description
    }
}

public struct FlightRoute: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let origin: AirportCode
    public let destination: AirportCode

    public init(origin: AirportCode, destination: AirportCode) {
        precondition(origin != destination, "A flight route must connect different airports")
        self.origin = origin
        self.destination = destination
    }

    public var description: String {
        "<FlightRoute redacted>"
    }

    public var debugDescription: String {
        description
    }
}

public struct FlightRouteQuery: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let callsign: FlightCallsign

    public init(callsign: FlightCallsign) {
        self.callsign = callsign
    }

    public var description: String {
        "<FlightRouteQuery redacted>"
    }

    public var debugDescription: String {
        description
    }
}

public protocol FlightRouteSource: Sendable {
    func routes(for queries: [FlightRouteQuery]) async throws -> [FlightCallsign: FlightRoute]
}

public enum FlightRouteLookupError: Error, Equatable, Sendable {
    case provider
    case transport(AircraftTransportErrorCategory)
    case decoding
}
