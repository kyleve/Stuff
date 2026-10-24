import Foundation

public struct AirportID: Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        precondition(rawValue > 0, "An airport ID must be positive")
        self.rawValue = rawValue
    }

    public var layerMarkID: LayerMarkID {
        .airport(self)
    }
}

public struct RunwayRecord: Hashable, Sendable {
    public let id: Int
    public let lengthFeet: Int
    public let lowEnd: GeoCoordinate
    public let highEnd: GeoCoordinate

    public init(id: Int, lengthFeet: Int, lowEnd: GeoCoordinate, highEnd: GeoCoordinate) {
        precondition(id > 0 && lengthFeet > 0)
        self.id = id
        self.lengthFeet = lengthFeet
        self.lowEnd = lowEnd
        self.highEnd = highEnd
    }
}

public struct AirportRecord: Hashable, Sendable {
    public let id: AirportID
    public let coordinate: GeoCoordinate
    public let elevation: Altitude?
    public let codes: [AirportCode]
    public let runways: [RunwayRecord]

    public init(
        id: AirportID,
        coordinate: GeoCoordinate,
        elevation: Altitude?,
        codes: [AirportCode],
        runways: [RunwayRecord],
    ) {
        precondition(codes.isEmpty == false)
        self.id = id
        self.coordinate = coordinate
        self.elevation = elevation
        self.codes = codes
        self.runways = runways
    }

    public var displayCode: AirportCode {
        codes.sorted {
            if $0.rawValue.count != $1.rawValue.count {
                return $0.rawValue.count < $1.rawValue.count
            }
            return $0.rawValue < $1.rawValue
        }.first!
    }

    public var longestOpenRunway: RunwayRecord? {
        runways.max { $0.lengthFeet < $1.lengthFeet }
    }
}

public enum FlightActivityStage: String, Hashable, Sendable {
    case inbound
    case approach
    case outbound
    case initialClimb = "initial-climb"
}

public enum FlightActivityCertainty: String, Hashable, Sendable {
    case confirmed
    case inferred
}

public struct AirportActivityContext: Hashable, Sendable {
    public let airport: AirportRecord
    public let aircraftDistance: NauticalMiles

    public init(airport: AirportRecord, aircraftDistance: NauticalMiles) {
        self.airport = airport
        self.aircraftDistance = aircraftDistance
    }
}

public enum FlightActivity: Hashable, Sendable {
    case overflight
    case arrival(AirportActivityContext, FlightActivityStage, FlightActivityCertainty)
    case departure(AirportActivityContext, FlightActivityStage, FlightActivityCertainty)

    public var airportContext: AirportActivityContext? {
        switch self {
            case .overflight: nil
            case let .arrival(context, _, _), let .departure(context, _, _): context
        }
    }

    public var certainty: FlightActivityCertainty? {
        switch self {
            case .overflight: nil
            case let .arrival(_, _, certainty), let .departure(_, _, certainty): certainty
        }
    }
}

public struct AirportGlyphDescriptor: Hashable, Sendable {
    public let airportID: AirportID
    public let code: AirportCode?
    public let runwayBearing: Bearing?
    public let certainty: FlightActivityCertainty

    public init(
        airportID: AirportID,
        code: AirportCode?,
        runwayBearing: Bearing?,
        certainty: FlightActivityCertainty,
    ) {
        self.airportID = airportID
        self.code = code
        self.runwayBearing = runwayBearing
        self.certainty = certainty
    }
}
