import Foundation

public struct TransitAgencyID: Hashable, Sendable {
    public static let mtaNewYorkCityTransit = TransitAgencyID(unchecked: "mta-nyct")

    public let rawValue: String

    public init?(rawValue: String) {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.isEmpty == false else { return nil }
        self.rawValue = value
    }

    private init(unchecked rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct TransitCityID: Hashable, Sendable {
    public static let newYorkCity = TransitCityID(unchecked: "new-york-city")

    public let rawValue: String

    public init?(rawValue: String) {
        switch rawValue {
            case Self.newYorkCity.rawValue: self = .newYorkCity
            default: return nil
        }
    }

    private init(unchecked rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct TransitRouteID: Hashable, Sendable {
    public let agencyID: TransitAgencyID
    public let rawValue: String

    public init?(agencyID: TransitAgencyID, rawValue: String) {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.isEmpty == false else { return nil }
        self.agencyID = agencyID
        self.rawValue = value
    }
}

public struct TransitStopID: Hashable, Sendable {
    public let agencyID: TransitAgencyID
    public let rawValue: String

    public init?(agencyID: TransitAgencyID, rawValue: String) {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.isEmpty == false else { return nil }
        self.agencyID = agencyID
        self.rawValue = value
    }

    public var parentStationID: TransitStopID {
        guard let suffix = rawValue.last, suffix == "N" || suffix == "S" else { return self }
        return TransitStopID(agencyID: agencyID, rawValue: String(rawValue.dropLast())) ?? self
    }
}

public struct TransitTripID: Hashable, Sendable {
    public let agencyID: TransitAgencyID
    public let rawValue: String

    public init?(agencyID: TransitAgencyID, rawValue: String) {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.isEmpty == false else { return nil }
        self.agencyID = agencyID
        self.rawValue = value
    }
}

public struct TransitFeedPartitionID: Hashable, Sendable {
    public let rawValue: String

    public init?(rawValue: String) {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.isEmpty == false else { return nil }
        self.rawValue = value
    }
}

public struct TransitRunID: Hashable, Sendable {
    public let agencyID: TransitAgencyID
    public let partitionID: TransitFeedPartitionID
    public let serviceDate: String
    public let stableRunValue: String

    public init?(
        agencyID: TransitAgencyID,
        partitionID: TransitFeedPartitionID,
        serviceDate: String,
        stableRunValue: String,
    ) {
        guard serviceDate.isEmpty == false, stableRunValue.isEmpty == false else { return nil }
        self.agencyID = agencyID
        self.partitionID = partitionID
        self.serviceDate = serviceDate
        self.stableRunValue = stableRunValue
    }
}

public struct TransitColor: Hashable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init?(hex: String) {
        let value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count == 6, let raw = UInt32(value, radix: 16) else { return nil }
        red = Double((raw >> 16) & 0xFF) / 255
        green = Double((raw >> 8) & 0xFF) / 255
        blue = Double(raw & 0xFF) / 255
    }

    public var hex: String {
        String(
            format: "%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded()),
        )
    }
}

public enum TransitLabelMode: String, CaseIterable, Hashable, Sendable {
    case routeOnly = "route-only"
    case destination
    case nextStop = "next-stop"
}

/// A Transit Map radius. Transit cannot request the Air & Space 240-NM range.
public struct TransitMapViewport: Hashable, Sendable {
    public static let allowedRadius = 5.0 ... 50.0
    public static let defaultValue = try! TransitMapViewport(
        radius: NauticalMiles(value: 20),
    )

    public let radius: NauticalMiles

    public init(radius: NauticalMiles) throws {
        guard Self.allowedRadius.contains(radius.value),
              radius.value.truncatingRemainder(dividingBy: 5) == 0
        else { throw ThrowValidationError.invalidPreferencePayload }
        self.radius = radius
    }

    public var projectionViewport: MapViewport {
        do {
            return try MapViewport(radius: radius)
        } catch {
            preconditionFailure("A validated Transit viewport must be a valid Map viewport")
        }
    }
}

public struct TransitStop: Hashable, Sendable {
    public let id: TransitStopID
    public let name: String
    public let coordinate: GeoCoordinate

    public init(id: TransitStopID, name: String, coordinate: GeoCoordinate) {
        precondition(name.isEmpty == false)
        self.id = id
        self.name = name
        self.coordinate = coordinate
    }
}

public struct TransitRoute: Hashable, Sendable {
    public let id: TransitRouteID
    public let shortName: String
    public let color: TransitColor

    public init(id: TransitRouteID, shortName: String, color: TransitColor) {
        precondition(shortName.isEmpty == false)
        self.id = id
        self.shortName = shortName
        self.color = color
    }
}

public struct TransitShapePoint: Hashable, Sendable {
    public let coordinate: GeoCoordinate
    public let distanceTraveled: Double

    public init(coordinate: GeoCoordinate, distanceTraveled: Double) {
        precondition(distanceTraveled.isFinite && distanceTraveled >= 0)
        self.coordinate = coordinate
        self.distanceTraveled = distanceTraveled
    }
}

public struct TransitTripPattern: Hashable, Sendable {
    public struct Stop: Hashable, Sendable {
        public let stopID: TransitStopID
        public let sequence: Int
        public let arrivalSeconds: Int
        public let departureSeconds: Int
        public let shapeDistanceTraveled: Double?

        public init(
            stopID: TransitStopID,
            sequence: Int,
            arrivalSeconds: Int,
            departureSeconds: Int,
            shapeDistanceTraveled: Double?,
        ) {
            precondition(sequence >= 0)
            precondition(arrivalSeconds >= 0 && departureSeconds >= arrivalSeconds)
            self.stopID = stopID
            self.sequence = sequence
            self.arrivalSeconds = arrivalSeconds
            self.departureSeconds = departureSeconds
            self.shapeDistanceTraveled = shapeDistanceTraveled
        }
    }

    public let tripID: TransitTripID
    public let routeID: TransitRouteID
    public let direction: Int
    public let headsign: String?
    public let shapeID: String
    public let stops: [Stop]

    public init(
        tripID: TransitTripID,
        routeID: TransitRouteID,
        direction: Int,
        headsign: String?,
        shapeID: String,
        stops: [Stop],
    ) {
        precondition((0 ... 1).contains(direction))
        precondition(shapeID.isEmpty == false && stops.count >= 2)
        precondition(stops.map(\.sequence) == stops.map(\.sequence).sorted())
        self.tripID = tripID
        self.routeID = routeID
        self.direction = direction
        self.headsign = headsign
        self.shapeID = shapeID
        self.stops = stops
    }
}

public struct TransitSchedule: Hashable, Sendable {
    public let agencyID: TransitAgencyID
    public let revision: String
    public let fetchedAt: Date
    public let routes: [TransitRouteID: TransitRoute]
    public let stops: [TransitStopID: TransitStop]
    public let tripPatterns: [TransitTripPattern]
    public let shapes: [String: [TransitShapePoint]]

    public init(
        agencyID: TransitAgencyID,
        revision: String,
        fetchedAt: Date,
        routes: [TransitRouteID: TransitRoute],
        stops: [TransitStopID: TransitStop],
        tripPatterns: [TransitTripPattern],
        shapes: [String: [TransitShapePoint]],
    ) {
        precondition(revision.isEmpty == false)
        precondition(routes.isEmpty == false && stops.isEmpty == false)
        precondition(tripPatterns.isEmpty == false && shapes.isEmpty == false)
        self.agencyID = agencyID
        self.revision = revision
        self.fetchedAt = fetchedAt
        self.routes = routes
        self.stops = stops
        self.tripPatterns = tripPatterns
        self.shapes = shapes
    }
}

public enum TransitPositionConfidence: Hashable, Sendable {
    case feedTracked
    case scheduleInferred
}

public struct TransitStopTimePrediction: Hashable, Sendable {
    public let stopID: TransitStopID
    public let arrival: Date?
    public let departure: Date?

    public init(stopID: TransitStopID, arrival: Date?, departure: Date?) {
        self.stopID = stopID
        self.arrival = arrival
        self.departure = departure
    }
}

public struct TransitRunObservation: Hashable, Sendable {
    public let id: TransitRunID
    public let tripID: TransitTripID?
    public let routeID: TransitRouteID
    public let direction: Int?
    public let observedAt: Date
    public let upcomingStops: [TransitStopTimePrediction]

    public init(
        id: TransitRunID,
        tripID: TransitTripID?,
        routeID: TransitRouteID,
        direction: Int?,
        observedAt: Date,
        upcomingStops: [TransitStopTimePrediction],
    ) {
        if let direction {
            precondition((0 ... 1).contains(direction))
        }
        precondition(upcomingStops.isEmpty == false)
        self.id = id
        self.tripID = tripID
        self.routeID = routeID
        self.direction = direction
        self.observedAt = observedAt
        self.upcomingStops = upcomingStops
    }
}

public struct TransitPartitionSnapshot: Hashable, Sendable {
    public let partitionID: TransitFeedPartitionID
    public let generatedAt: Date
    public let fetchedAt: Date
    public let runs: [TransitRunObservation]

    public init(
        partitionID: TransitFeedPartitionID,
        generatedAt: Date,
        fetchedAt: Date,
        runs: [TransitRunObservation],
    ) {
        self.partitionID = partitionID
        self.generatedAt = generatedAt
        self.fetchedAt = fetchedAt
        self.runs = runs
    }
}

public enum TransitDataError: Error, Equatable, Sendable {
    case invalidSchedule
    case invalidRealtime
    case unavailable
    case server(statusCode: Int)
}
