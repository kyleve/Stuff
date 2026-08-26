import Foundation

public enum GeographyLineKind: String, CaseIterable, Codable, Hashable, Sendable {
    case coastline
    case lake
    case river
    case nationalBoundary = "national-boundary"
    case disputedBoundary = "disputed-boundary"
    case regionalBoundary = "regional-boundary"
    case countyBoundary = "county-boundary"
    case primaryRoad = "primary-road"
}

/// A stable style identity shared by geographic and future network line layers.
public struct ProjectionLineStyleID: Hashable, Sendable {
    public static let transitRoute = ProjectionLineStyleID(rawValue: "transit.route")

    public let rawValue: String

    public init(rawValue: String) {
        precondition(rawValue.isEmpty == false)
        self.rawValue = rawValue
    }

    public init(geographyKind: GeographyLineKind) {
        self.init(rawValue: "geography.\(geographyKind.rawValue)")
    }

    public var geographyKind: GeographyLineKind? {
        let prefix = "geography."
        guard rawValue.hasPrefix(prefix) else { return nil }
        return GeographyLineKind(rawValue: String(rawValue.dropFirst(prefix.count)))
    }
}

/// Controls the largest Map radius at which a geographic line can appear.
public enum GeographyDetailLevel: String, CaseIterable, Codable, Hashable, Sendable {
    case wide
    case standard
    case local

    public func includes(mapRadius: NauticalMiles) -> Bool {
        switch self {
            case .wide:
                mapRadius.value <= 240
            case .standard:
                mapRadius.value <= 80
            case .local:
                mapRadius.value <= 20
        }
    }
}

/// A non-wrapping WGS84 bounding box. Bundled paths split at the antimeridian.
public struct GeographicBounds: Hashable, Sendable {
    public let southLatitude: Double
    public let westLongitude: Double
    public let northLatitude: Double
    public let eastLongitude: Double

    public init(
        southLatitude: Double,
        westLongitude: Double,
        northLatitude: Double,
        eastLongitude: Double,
    ) throws {
        guard southLatitude.isFinite, westLongitude.isFinite,
              northLatitude.isFinite, eastLongitude.isFinite,
              (-90 ... 90).contains(southLatitude),
              (-90 ... 90).contains(northLatitude),
              (-180 ... 180).contains(westLongitude),
              (-180 ... 180).contains(eastLongitude),
              southLatitude <= northLatitude,
              westLongitude <= eastLongitude
        else {
            throw GeographyDataError.invalidArchive
        }
        self.southLatitude = southLatitude
        self.westLongitude = westLongitude
        self.northLatitude = northLatitude
        self.eastLongitude = eastLongitude
    }
}

/// A generalized geographic line used by static context and future route layers.
public struct ProjectionPolyline: Hashable, Sendable {
    public let styleID: ProjectionLineStyleID
    public let detailLevel: GeographyDetailLevel
    public let bounds: GeographicBounds
    public let coordinates: [GeoCoordinate]

    public init(
        styleID: ProjectionLineStyleID,
        detailLevel: GeographyDetailLevel,
        bounds: GeographicBounds,
        coordinates: [GeoCoordinate],
    ) throws {
        guard coordinates.count >= 2,
              coordinates.allSatisfy({ coordinate in
                  (bounds.southLatitude ... bounds.northLatitude).contains(coordinate.latitude) &&
                      (bounds.westLongitude ... bounds.eastLongitude).contains(
                          coordinate.longitude,
                      )
              })
        else {
            throw GeographyDataError.invalidArchive
        }
        self.styleID = styleID
        self.detailLevel = detailLevel
        self.bounds = bounds
        self.coordinates = coordinates
    }

    public init(
        kind: GeographyLineKind,
        detailLevel: GeographyDetailLevel,
        bounds: GeographicBounds,
        coordinates: [GeoCoordinate],
    ) throws {
        try self.init(
            styleID: ProjectionLineStyleID(geographyKind: kind),
            detailLevel: detailLevel,
            bounds: bounds,
            coordinates: coordinates,
        )
    }

    public var kind: GeographyLineKind {
        guard let kind = styleID.geographyKind else {
            preconditionFailure("A non-geographic line style has no Geography kind")
        }
        return kind
    }
}

public typealias GeographicPolyline = ProjectionPolyline

public enum GeographyDataError: Error, Equatable, Sendable {
    case resourceMissing
    case invalidArchive
}
