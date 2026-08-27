import Foundation

public protocol TransitScheduleStore: Sendable {
    func load() async throws -> TransitSchedule?
    func save(_ schedule: TransitSchedule) async throws
}

public actor FileTransitScheduleStore: TransitScheduleStore {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> TransitSchedule? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            return try PropertyListDecoder().decode(Storage.self, from: data).value()
        } catch {
            throw TransitDataError.invalidSchedule
        }
    }

    public func save(_ schedule: TransitSchedule) throws {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
            )
            let data = try PropertyListEncoder().encode(Storage(schedule))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw TransitDataError.unavailable
        }
    }
}

public actor InMemoryTransitScheduleStore: TransitScheduleStore {
    private var schedule: TransitSchedule?

    public init(schedule: TransitSchedule?) {
        self.schedule = schedule
    }

    public func load() -> TransitSchedule? {
        schedule
    }

    public func save(_ schedule: TransitSchedule) {
        self.schedule = schedule
    }
}

private struct Storage: Codable {
    let version: Int
    let agencyID: String
    let revision: String
    let fetchedAt: Date
    let routes: [RouteStorage]
    let stops: [StopStorage]
    let tripPatterns: [TripPatternStorage]
    let shapes: [ShapeStorage]

    init(_ schedule: TransitSchedule) {
        version = 1
        agencyID = schedule.agencyID.rawValue
        revision = schedule.revision
        fetchedAt = schedule.fetchedAt
        routes = schedule.routes.values.map(RouteStorage.init)
        stops = schedule.stops.values.map(StopStorage.init)
        tripPatterns = schedule.tripPatterns.map(TripPatternStorage.init)
        shapes = schedule.shapes.map { ShapeStorage(id: $0.key, points: $0.value) }
    }

    func value() throws -> TransitSchedule {
        guard version == 1,
              let agencyID = TransitAgencyID(rawValue: agencyID),
              revision.isEmpty == false
        else { throw TransitDataError.invalidSchedule }
        let decodedRoutes = try routes.map { try $0.value(agencyID: agencyID) }
        let decodedStops = try stops.map { try $0.value(agencyID: agencyID) }
        let decodedPatterns = try tripPatterns.map { try $0.value(agencyID: agencyID) }
        let decodedShapes = try shapes.map { try ($0.id, $0.value()) }
        let routeDictionary = try uniqueDictionary(decodedRoutes.map { ($0.id, $0) })
        let stopDictionary = try uniqueDictionary(decodedStops.map { ($0.id, $0) })
        let shapeDictionary = try uniqueDictionary(decodedShapes)
        guard decodedPatterns.isEmpty == false,
              decodedPatterns.allSatisfy({ pattern in
                  routeDictionary[pattern.routeID] != nil &&
                      shapeDictionary[pattern.shapeID] != nil &&
                      pattern.stops.allSatisfy { stop in
                          stopDictionary[stop.stopID] != nil ||
                              stopDictionary[stop.stopID.parentStationID] != nil
                      }
              }),
              routeDictionary.isEmpty == false,
              stopDictionary.isEmpty == false,
              shapeDictionary.isEmpty == false,
              shapeDictionary.values.allSatisfy({ points in
                  points.count >= 2 &&
                      zip(points, points.dropFirst()).allSatisfy {
                          $0.distanceTraveled <= $1.distanceTraveled
                      }
              })
        else { throw TransitDataError.invalidSchedule }
        return TransitSchedule(
            agencyID: agencyID,
            revision: revision,
            fetchedAt: fetchedAt,
            routes: routeDictionary,
            stops: stopDictionary,
            tripPatterns: decodedPatterns,
            shapes: shapeDictionary,
        )
    }

    private func uniqueDictionary<Key: Hashable, Value>(
        _ values: [(Key, Value)],
    ) throws -> [Key: Value] {
        var result: [Key: Value] = [:]
        for (key, value) in values {
            guard result.updateValue(value, forKey: key) == nil else {
                throw TransitDataError.invalidSchedule
            }
        }
        return result
    }
}

private struct RouteStorage: Codable {
    let id: String
    let shortName: String
    let color: String

    init(_ route: TransitRoute) {
        id = route.id.rawValue
        shortName = route.shortName
        color = route.color.hex
    }

    func value(agencyID: TransitAgencyID) throws -> TransitRoute {
        guard let id = TransitRouteID(agencyID: agencyID, rawValue: id),
              let color = TransitColor(hex: color),
              shortName.isEmpty == false
        else { throw TransitDataError.invalidSchedule }
        return TransitRoute(id: id, shortName: shortName, color: color)
    }
}

private struct StopStorage: Codable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double

    init(_ stop: TransitStop) {
        id = stop.id.rawValue
        name = stop.name
        latitude = stop.coordinate.latitude
        longitude = stop.coordinate.longitude
    }

    func value(agencyID: TransitAgencyID) throws -> TransitStop {
        guard let id = TransitStopID(agencyID: agencyID, rawValue: id),
              name.isEmpty == false
        else {
            throw TransitDataError.invalidSchedule
        }
        return try TransitStop(
            id: id,
            name: name,
            coordinate: GeoCoordinate(latitude: latitude, longitude: longitude),
        )
    }
}

private struct TripPatternStorage: Codable {
    struct PatternStopStorage: Codable {
        let stopID: String
        let sequence: Int
        let arrivalSeconds: Int
        let departureSeconds: Int
        let shapeDistanceTraveled: Double?

        init(_ stop: TransitTripPattern.Stop) {
            stopID = stop.stopID.rawValue
            sequence = stop.sequence
            arrivalSeconds = stop.arrivalSeconds
            departureSeconds = stop.departureSeconds
            shapeDistanceTraveled = stop.shapeDistanceTraveled
        }

        func value(agencyID: TransitAgencyID) throws -> TransitTripPattern.Stop {
            guard let stopID = TransitStopID(agencyID: agencyID, rawValue: stopID),
                  sequence >= 0,
                  arrivalSeconds >= 0,
                  departureSeconds >= arrivalSeconds,
                  shapeDistanceTraveled.map({ $0.isFinite && $0 >= 0 }) ?? true
            else {
                throw TransitDataError.invalidSchedule
            }
            return TransitTripPattern.Stop(
                stopID: stopID,
                sequence: sequence,
                arrivalSeconds: arrivalSeconds,
                departureSeconds: departureSeconds,
                shapeDistanceTraveled: shapeDistanceTraveled,
            )
        }
    }

    let tripID: String
    let routeID: String
    let direction: Int
    let headsign: String?
    let shapeID: String
    let stops: [PatternStopStorage]

    init(_ pattern: TransitTripPattern) {
        tripID = pattern.tripID.rawValue
        routeID = pattern.routeID.rawValue
        direction = pattern.direction
        headsign = pattern.headsign
        shapeID = pattern.shapeID
        stops = pattern.stops.map(PatternStopStorage.init)
    }

    func value(agencyID: TransitAgencyID) throws -> TransitTripPattern {
        guard let tripID = TransitTripID(agencyID: agencyID, rawValue: tripID),
              let routeID = TransitRouteID(agencyID: agencyID, rawValue: routeID),
              (0 ... 1).contains(direction),
              shapeID.isEmpty == false,
              stops.count >= 2,
              stops.map(\.sequence) == stops.map(\.sequence).sorted()
        else { throw TransitDataError.invalidSchedule }
        return try TransitTripPattern(
            tripID: tripID,
            routeID: routeID,
            direction: direction,
            headsign: headsign,
            shapeID: shapeID,
            stops: stops.map { try $0.value(agencyID: agencyID) },
        )
    }
}

private struct ShapeStorage: Codable {
    struct PointStorage: Codable {
        let latitude: Double
        let longitude: Double
        let distanceTraveled: Double

        init(_ point: TransitShapePoint) {
            latitude = point.coordinate.latitude
            longitude = point.coordinate.longitude
            distanceTraveled = point.distanceTraveled
        }

        func value() throws -> TransitShapePoint {
            guard distanceTraveled.isFinite, distanceTraveled >= 0 else {
                throw TransitDataError.invalidSchedule
            }
            return try TransitShapePoint(
                coordinate: GeoCoordinate(latitude: latitude, longitude: longitude),
                distanceTraveled: distanceTraveled,
            )
        }
    }

    let id: String
    let points: [PointStorage]

    init(id: String, points: [TransitShapePoint]) {
        self.id = id
        self.points = points.map(PointStorage.init)
    }

    func value() throws -> [TransitShapePoint] {
        try points.map { try $0.value() }
    }
}
