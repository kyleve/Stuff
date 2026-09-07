import Foundation

/// An immutable, spatially indexed catalog of airports and open runways.
public struct AirportCatalog: Sendable {
    public static let bundled: AirportCatalog = {
        guard let url = Bundle.module.url(forResource: "airports-v1", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let archive = try? JSONDecoder().decode(Archive.self, from: data),
              let catalog = try? AirportCatalog(archive: archive)
        else {
            preconditionFailure("The bundled airport catalog is invalid")
        }
        return catalog
    }()

    public let airports: [AirportRecord]
    private let byCode: [AirportCode: [AirportRecord]]
    private let spatialIndex: [Cell: [AirportRecord]]

    public init(airports: [AirportRecord]) {
        self.airports = airports
        var index: [AirportCode: [AirportRecord]] = [:]
        for airport in airports {
            for code in airport.codes {
                index[code, default: []].append(airport)
            }
        }
        byCode = index
        spatialIndex = Dictionary(grouping: airports) { Cell(coordinate: $0.coordinate) }
    }

    public func airport(
        for code: AirportCode,
        near observer: ObserverPosition,
    ) throws -> AirportRecord? {
        var nearest: (airport: AirportRecord, distance: NauticalMiles)?
        for airport in byCode[code] ?? [] {
            let candidateDistance = try distance(
                from: observer.coordinate,
                to: airport.coordinate,
            )
            if nearest == nil || candidateDistance < nearest!.distance {
                nearest = (airport, candidateDistance)
            }
        }
        return nearest?.airport
    }

    public func airports(
        within radius: NauticalMiles,
        of coordinate: GeoCoordinate,
    ) throws -> [AirportRecord] {
        let latitudeSpan = Int(ceil(radius.value / 60)) + 1
        let longitudeScale = max(0.05, cos(coordinate.latitude * .pi / 180))
        let longitudeSpan = min(180, Int(ceil(radius.value / (60 * longitudeScale))) + 1)
        let center = Cell(coordinate: coordinate)
        var candidates: [AirportRecord] = []
        for latitude in max(-90, center.latitude - latitudeSpan) ...
            min(89, center.latitude + latitudeSpan)
        {
            for offset in -longitudeSpan ... longitudeSpan {
                var longitude = center.longitude + offset
                while longitude < -180 {
                    longitude += 360
                }
                while longitude > 179 {
                    longitude -= 360
                }
                candidates.append(contentsOf: spatialIndex[Cell(
                    latitude: latitude,
                    longitude: longitude,
                )] ?? [])
            }
        }
        return try candidates.filter { try distance(from: coordinate, to: $0.coordinate) <= radius }
    }

    public func distance(
        from source: GeoCoordinate,
        to target: GeoCoordinate,
    ) throws -> NauticalMiles {
        try ProjectionEngine().greatCirclePosition(from: source, to: target).distance
    }

    private init(archive: Archive) throws {
        guard archive.v == 1 else { throw AirportCatalogError.unsupportedVersion }
        let records = try archive.airports.map { row -> AirportRecord in
            guard row.count == 6,
                  let id = row[0].int,
                  let latitude = row[1].double,
                  let longitude = row[2].double,
                  let codeRows = row[4].strings,
                  let runwayRows = row[5].rows
            else { throw AirportCatalogError.invalidRecord }
            let elevation = try row[3].double.map(Altitude.init(feet:))
            let codes = codeRows.compactMap(AirportCode.init(rawValue:))
            let runways = try runwayRows.map { runway -> RunwayRecord in
                guard runway.count == 6,
                      let runwayID = runway[0].int,
                      let length = runway[1].int,
                      let leLatitude = runway[2].double,
                      let leLongitude = runway[3].double,
                      let heLatitude = runway[4].double,
                      let heLongitude = runway[5].double
                else { throw AirportCatalogError.invalidRecord }
                return try RunwayRecord(
                    id: runwayID,
                    lengthFeet: length,
                    lowEnd: GeoCoordinate(latitude: leLatitude, longitude: leLongitude),
                    highEnd: GeoCoordinate(latitude: heLatitude, longitude: heLongitude),
                )
            }
            return try AirportRecord(
                id: AirportID(rawValue: id),
                coordinate: GeoCoordinate(latitude: latitude, longitude: longitude),
                elevation: elevation,
                codes: codes,
                runways: runways,
            )
        }
        self.init(airports: records)
    }
}

private struct Cell: Hashable {
    let latitude: Int
    let longitude: Int

    init(coordinate: GeoCoordinate) {
        latitude = min(89, Int(floor(coordinate.latitude)))
        longitude = coordinate.longitude == 180 ? 179 : Int(floor(coordinate.longitude))
    }

    init(latitude: Int, longitude: Int) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

private enum AirportCatalogError: Error { case unsupportedVersion, invalidRecord }

private struct Archive: Decodable { let v: Int; let revision: String; let airports: [[JSONValue]] }

private enum JSONValue: Decodable {
    case number(Double), string(String), array([JSONValue]), null
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else { self = try .array(container.decode([JSONValue].self)) }
    }

    var double: Double? {
        if case let .number(value) = self { value } else { nil }
    }

    var int: Int? {
        double.map(Int.init)
    }

    var strings: [String]? {
        if case let .array(values) = self {
            values.compactMap { if case let .string(value) = $0 { value } else { nil } }
        } else { nil }
    }

    var rows: [[JSONValue]]? {
        if case let .array(values) = self {
            values.compactMap { if case let .array(value) = $0 { value } else { nil } }
        } else { nil }
    }
}
