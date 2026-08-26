import Foundation

/// A coarse geographic bucket used to select a fixed Map center without
/// persisting behavior against an exact observer coordinate.
public struct MapRegionID: Hashable, Sendable, CustomStringConvertible {
    public let latitudeBand: Int
    public let longitudeBand: Int

    public init(containing coordinate: GeoCoordinate) {
        latitudeBand = Int(floor(coordinate.latitude))
        longitudeBand = Int(floor(coordinate.longitude))
    }

    public init(latitudeBand: Int, longitudeBand: Int) throws {
        guard (-90 ... 89).contains(latitudeBand), (-180 ... 179).contains(longitudeBand) else {
            throw ThrowValidationError.invalidPreferencePayload
        }
        self.latitudeBand = latitudeBand
        self.longitudeBand = longitudeBand
    }

    public var description: String {
        "<MapRegionID redacted>"
    }
}

public struct MapCenterProfile: Hashable, Sendable, CustomStringConvertible {
    public let regionID: MapRegionID
    public let center: GeoCoordinate

    public init(regionID: MapRegionID, center: GeoCoordinate) {
        self.regionID = regionID
        self.center = center
    }

    public var description: String {
        "<MapCenterProfile location=<redacted>>"
    }
}

/// Fixed Map centers keyed by coarse observer region. True Sky never reads
/// these values.
public struct MapCenterPreferences: Hashable, Sendable, CustomStringConvertible {
    public static let defaultValue = try! MapCenterPreferences(profiles: [])

    public let profiles: [MapCenterProfile]

    public init(profiles: [MapCenterProfile]) throws {
        guard Set(profiles.map(\.regionID)).count == profiles.count else {
            throw ThrowValidationError.invalidPreferencePayload
        }
        self.profiles = profiles.sorted {
            if $0.regionID.latitudeBand == $1.regionID.latitudeBand {
                $0.regionID.longitudeBand < $1.regionID.longitudeBand
            } else {
                $0.regionID.latitudeBand < $1.regionID.latitudeBand
            }
        }
    }

    public func center(for observer: GeoCoordinate) -> GeoCoordinate {
        let regionID = MapRegionID(containing: observer)
        return profiles.first { $0.regionID == regionID }?.center ?? observer
    }

    public func setting(center: GeoCoordinate, for observer: GeoCoordinate) -> Self {
        let regionID = MapRegionID(containing: observer)
        let profile = MapCenterProfile(regionID: regionID, center: center)
        return try! Self(profiles: profiles.filter { $0.regionID != regionID } + [profile])
    }

    public func resetting(for observer: GeoCoordinate) -> Self {
        let regionID = MapRegionID(containing: observer)
        return try! Self(profiles: profiles.filter { $0.regionID != regionID })
    }

    public var description: String {
        "<MapCenterPreferences count=\(profiles.count) locations=<redacted>>"
    }
}
