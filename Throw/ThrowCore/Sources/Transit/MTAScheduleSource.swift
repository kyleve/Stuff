import Foundation
import ZIPFoundation

public protocol TransitScheduleSource: Sendable {
    func schedule(fetchedAt: Date) async throws -> TransitSchedule
}

public struct MTAScheduleSource: TransitScheduleSource {
    public static let supplementedScheduleURL: URL = {
        guard let value = URL(
            string: "https://rrgtfsfeeds.s3.amazonaws.com/gtfs_supplemented.zip",
        ) else {
            preconditionFailure("The bundled MTA schedule URL must be valid")
        }
        return value
    }()

    private let transport: any HTTPTransport

    public init(transport: any HTTPTransport) {
        self.transport = transport
    }

    public func schedule(fetchedAt: Date) async throws -> TransitSchedule {
        let response = try await transport.response(for: HTTPRequest(
            method: .get,
            url: Self.supplementedScheduleURL,
            headers: [.accept: "application/zip"],
            timeoutSeconds: 20,
        ))
        guard response.statusCode == 200 else {
            throw TransitDataError.server(statusCode: response.statusCode)
        }
        return try Self.decode(
            response.data,
            fetchedAt: fetchedAt,
            revision: response.headerValue(for: "etag") ?? Self.digest(response.data),
        )
    }

    static func decode(
        _ archiveData: Data,
        fetchedAt: Date,
        revision: String,
    ) throws -> TransitSchedule {
        let archive: Archive
        do {
            archive = try Archive(data: archiveData, accessMode: .read, pathEncoding: nil)
        } catch {
            throw TransitDataError.invalidSchedule
        }
        let routesCSV = try csv(named: "routes.txt", in: archive)
        let stopsCSV = try csv(named: "stops.txt", in: archive)
        let shapesCSV = try csv(named: "shapes.txt", in: archive)
        let tripsCSV = try csv(named: "trips.txt", in: archive)
        let stopTimesCSV = try csv(named: "stop_times.txt", in: archive)
        let agencyID = TransitAgencyID.mtaNewYorkCityTransit

        var routes: [TransitRouteID: TransitRoute] = [:]
        for row in try routesCSV.values() {
            guard let rawID = row["route_id"],
                  let id = TransitRouteID(agencyID: agencyID, rawValue: rawID),
                  let shortName = row["route_short_name"], shortName.isEmpty == false,
                  let rawColor = row["route_color"],
                  let color = TransitColor(hex: rawColor)
            else { throw TransitDataError.invalidSchedule }
            guard routes.updateValue(
                TransitRoute(id: id, shortName: shortName, color: color),
                forKey: id,
            ) == nil else { throw TransitDataError.invalidSchedule }
        }

        var stops: [TransitStopID: TransitStop] = [:]
        for row in try stopsCSV.values() {
            guard let rawID = row["stop_id"],
                  let id = TransitStopID(agencyID: agencyID, rawValue: rawID),
                  let name = row["stop_name"], name.isEmpty == false,
                  let latitude = row["stop_lat"].flatMap(Double.init),
                  let longitude = row["stop_lon"].flatMap(Double.init),
                  latitude.isFinite, (-90 ... 90).contains(latitude),
                  longitude.isFinite, (-180 ... 180).contains(longitude)
            else { throw TransitDataError.invalidSchedule }
            let coordinate = try GeoCoordinate(latitude: latitude, longitude: longitude)
            guard stops.updateValue(
                TransitStop(id: id, name: name, coordinate: coordinate),
                forKey: id,
            ) == nil
            else { throw TransitDataError.invalidSchedule }
        }

        struct RawShapePoint {
            let sequence: Int
            let coordinate: GeoCoordinate
            let distance: Double?
        }
        var rawShapes: [String: [RawShapePoint]] = [:]
        for row in try shapesCSV.values() {
            guard let shapeID = row["shape_id"], shapeID.isEmpty == false,
                  let latitude = row["shape_pt_lat"].flatMap(Double.init),
                  let longitude = row["shape_pt_lon"].flatMap(Double.init),
                  let sequence = row["shape_pt_sequence"].flatMap(Int.init),
                  sequence >= 0,
                  latitude.isFinite, (-90 ... 90).contains(latitude),
                  longitude.isFinite, (-180 ... 180).contains(longitude)
            else { throw TransitDataError.invalidSchedule }
            let coordinate = try GeoCoordinate(latitude: latitude, longitude: longitude)
            rawShapes[shapeID, default: []].append(RawShapePoint(
                sequence: sequence,
                coordinate: coordinate,
                distance: row["shape_dist_traveled"].flatMap(Double.init),
            ))
        }
        guard rawShapes.values.allSatisfy({ points in
            Set(points.map(\.sequence)).count == points.count
        }) else { throw TransitDataError.invalidSchedule }
        let shapes = rawShapes.mapValues { points in
            let ordered = points.sorted { $0.sequence < $1.sequence }
            let suppliedDistances = ordered.compactMap(\.distance)
            let usesSuppliedDistances = suppliedDistances.count == ordered.count &&
                suppliedDistances.allSatisfy { $0.isFinite && $0 >= 0 } &&
                zip(suppliedDistances, suppliedDistances.dropFirst()).allSatisfy {
                    $0 <= $1
                }
            var distance = 0.0
            var previous: GeoCoordinate?
            return ordered.map { point in
                if usesSuppliedDistances, let supplied = point.distance {
                    distance = supplied
                } else if let previous {
                    distance += nauticalMiles(from: previous, to: point.coordinate)
                }
                previous = point.coordinate
                return TransitShapePoint(coordinate: point.coordinate, distanceTraveled: distance)
            }
        }
        guard shapes.values.allSatisfy({ $0.count >= 2 }) else {
            throw TransitDataError.invalidSchedule
        }

        struct RawTrip {
            let id: TransitTripID
            let routeID: TransitRouteID
            let direction: Int
            let headsign: String?
            let shapeID: String
        }
        var trips: [TransitTripID: RawTrip] = [:]
        for row in try tripsCSV.values() {
            guard let rawTripID = row["trip_id"],
                  let tripID = TransitTripID(agencyID: agencyID, rawValue: rawTripID),
                  let rawRouteID = row["route_id"],
                  let routeID = TransitRouteID(agencyID: agencyID, rawValue: rawRouteID),
                  routes[routeID] != nil,
                  let direction = row["direction_id"].flatMap(Int.init),
                  (0 ... 1).contains(direction),
                  let shapeID = row["shape_id"], shapes[shapeID] != nil
            else { continue }
            let headsign = row["trip_headsign"].flatMap { $0.isEmpty ? nil : $0 }
            guard trips.updateValue(RawTrip(
                id: tripID,
                routeID: routeID,
                direction: direction,
                headsign: headsign,
                shapeID: shapeID,
            ), forKey: tripID) == nil else { throw TransitDataError.invalidSchedule }
        }

        var stopTimes: [TransitTripID: [TransitTripPattern.Stop]] = [:]
        for row in try stopTimesCSV.values() {
            guard let rawTripID = row["trip_id"],
                  let tripID = TransitTripID(agencyID: agencyID, rawValue: rawTripID),
                  trips[tripID] != nil,
                  let rawStopID = row["stop_id"],
                  let stopID = TransitStopID(agencyID: agencyID, rawValue: rawStopID),
                  stops[stopID] != nil || stops[stopID.parentStationID] != nil,
                  let sequence = row["stop_sequence"].flatMap(Int.init),
                  let arrival = row["arrival_time"].flatMap(Self.serviceSeconds),
                  let departure = row["departure_time"].flatMap(Self.serviceSeconds)
            else { continue }
            stopTimes[tripID, default: []].append(TransitTripPattern.Stop(
                stopID: stopID,
                sequence: sequence,
                arrivalSeconds: arrival,
                departureSeconds: departure,
                shapeDistanceTraveled: row["shape_dist_traveled"].flatMap(Double.init),
            ))
        }

        let patterns = trips.values.compactMap { trip -> TransitTripPattern? in
            let orderedStops = (stopTimes[trip.id] ?? []).sorted { $0.sequence < $1.sequence }
            guard orderedStops.count >= 2,
                  Set(orderedStops.map(\.sequence)).count == orderedStops.count
            else { return nil }
            return TransitTripPattern(
                tripID: trip.id,
                routeID: trip.routeID,
                direction: trip.direction,
                headsign: trip.headsign,
                shapeID: trip.shapeID,
                stops: orderedStops,
            )
        }
        guard patterns.isEmpty == false else { throw TransitDataError.invalidSchedule }
        return TransitSchedule(
            agencyID: agencyID,
            revision: revision,
            fetchedAt: fetchedAt,
            routes: routes,
            stops: stops,
            tripPatterns: patterns,
            shapes: shapes,
        )
    }

    private static func csv(named name: String, in archive: Archive) throws -> TransitCSV {
        guard let entry = archive[name] else { throw TransitDataError.invalidSchedule }
        var data = Data()
        do {
            _ = try archive.extract(entry) { data.append($0) }
            return try TransitCSV(data: data)
        } catch let error as TransitDataError {
            throw error
        } catch {
            throw TransitDataError.invalidSchedule
        }
    }

    private static func serviceSeconds(_ value: String) -> Int? {
        let components = value.split(separator: ":").compactMap { Int($0) }
        guard components.count == 3,
              components[0] >= 0,
              (0 ... 59).contains(components[1]),
              (0 ... 59).contains(components[2])
        else { return nil }
        return components[0] * 3600 + components[1] * 60 + components[2]
    }

    private static func nauticalMiles(from lhs: GeoCoordinate, to rhs: GeoCoordinate) -> Double {
        let latitude1 = lhs.latitude * .pi / 180
        let latitude2 = rhs.latitude * .pi / 180
        let deltaLatitude = latitude2 - latitude1
        let deltaLongitude = (rhs.longitude - lhs.longitude) * .pi / 180
        let a = sin(deltaLatitude / 2) * sin(deltaLatitude / 2) +
            cos(latitude1) * cos(latitude2) * sin(deltaLongitude / 2) * sin(deltaLongitude / 2)
        return 3440.0695 * 2 * atan2(sqrt(a), sqrt(max(0, 1 - a)))
    }

    private static func digest(_ data: Data) -> String {
        var value: UInt64 = 14_695_981_039_346_656_037
        for byte in data {
            value ^= UInt64(byte)
            value &*= 1_099_511_628_211
        }
        return String(value, radix: 16)
    }
}
