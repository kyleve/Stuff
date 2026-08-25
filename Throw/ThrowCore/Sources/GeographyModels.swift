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

/// A generalized geographic line with enough metadata for local detail pruning.
public struct GeographicPolyline: Hashable, Sendable {
    public let kind: GeographyLineKind
    public let detailLevel: GeographyDetailLevel
    public let bounds: GeographicBounds
    public let coordinates: [GeoCoordinate]

    public init(
        kind: GeographyLineKind,
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
        self.kind = kind
        self.detailLevel = detailLevel
        self.bounds = bounds
        self.coordinates = coordinates
    }
}

public enum GeographyDataError: Error, Equatable, Sendable {
    case resourceMissing
    case invalidArchive
}
