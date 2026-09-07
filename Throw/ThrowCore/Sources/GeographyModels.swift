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

/// A style family carried by one semantic and projected line layer.
public protocol ProjectionLineStyle: Hashable, Sendable {}

extension GeographyLineKind: ProjectionLineStyle {}

/// The closed style family for the Transit network layer.
public struct TransitNetworkLineStyle: Hashable, Sendable, ProjectionLineStyle {
    public let routeID: TransitRouteID
    public let color: TransitColor

    public init(routeID: TransitRouteID, color: TransitColor) {
        self.routeID = routeID
        self.color = color
    }
}

public typealias TransitRouteLineStyle = TransitNetworkLineStyle

/// Controls the largest Map radius at which a geographic line can appear.
public enum GeographyDetailLevel: String, CaseIterable, Codable, Hashable, Sendable {
    case wide
    case standard
    case local
    case neighborhood

    public func includes(mapRadius: NauticalMiles) -> Bool {
        switch self {
            case .wide:
                mapRadius.value <= 240
            case .standard:
                mapRadius.value <= 80
            case .local:
                mapRadius.value <= 20
            case .neighborhood:
                mapRadius.value <= 8
        }
    }

    public var replacesBroaderDetail: Bool {
        switch self {
            case .wide, .standard, .local: false
            case .neighborhood: true
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

/// One validated line whose style family is fixed by its generic argument.
public struct ProjectionPolyline<Style: ProjectionLineStyle>: Hashable, Sendable {
    public let style: Style
    public let detailLevel: GeographyDetailLevel
    public let bounds: GeographicBounds
    public let coordinates: [GeoCoordinate]

    public init(
        style: Style,
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
        self.style = style
        self.detailLevel = detailLevel
        self.bounds = bounds
        self.coordinates = coordinates
    }
}

extension ProjectionPolyline where Style == GeographyLineKind {
    public init(
        kind: GeographyLineKind,
        detailLevel: GeographyDetailLevel,
        bounds: GeographicBounds,
        coordinates: [GeoCoordinate],
    ) throws {
        try self.init(
            style: kind,
            detailLevel: detailLevel,
            bounds: bounds,
            coordinates: coordinates,
        )
    }

    public var kind: GeographyLineKind {
        style
    }
}

public typealias GeographicPolyline = ProjectionPolyline<GeographyLineKind>

public enum GeographyDataError: Error, Equatable, Sendable {
    case resourceMissing
    case invalidArchive
}
