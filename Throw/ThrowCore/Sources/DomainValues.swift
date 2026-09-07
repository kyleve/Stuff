import Foundation

public enum ThrowValidationError: Error, Equatable, Sendable {
    case nonFiniteValue(field: String)
    case outOfRange(field: String, closedRange: ClosedRange<Double>)
    case invalidQuietInterval
    case invalidURL
    case invalidPreferencePayload
}

/// A validated WGS84 latitude/longitude pair in decimal degrees.
public struct GeoCoordinate: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) throws {
        guard latitude.isFinite else {
            throw ThrowValidationError.nonFiniteValue(field: "latitude")
        }
        guard longitude.isFinite else {
            throw ThrowValidationError.nonFiniteValue(field: "longitude")
        }
        guard (-90.0 ... 90.0).contains(latitude) else {
            throw ThrowValidationError.outOfRange(field: "latitude", closedRange: -90 ... 90)
        }
        guard (-180.0 ... 180.0).contains(longitude) else {
            throw ThrowValidationError.outOfRange(field: "longitude", closedRange: -180 ... 180)
        }
        self.latitude = latitude
        self.longitude = longitude
    }

    public var description: String {
        "<GeoCoordinate redacted>"
    }

    public var debugDescription: String {
        description
    }
}

/// A mean-sea-level altitude represented in feet.
public struct Altitude: Hashable, Sendable {
    public static let allowedFeet = -2000.0 ... 100_000.0

    public let feet: Double

    public init(feet: Double) throws {
        guard feet.isFinite else {
            throw ThrowValidationError.nonFiniteValue(field: "altitude")
        }
        guard Self.allowedFeet.contains(feet) else {
            throw ThrowValidationError.outOfRange(
                field: "altitude",
                closedRange: Self.allowedFeet,
            )
        }
        self.feet = feet
    }

    public var meters: Double {
        feet * 0.3048
    }
}

public struct ObserverPosition: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let coordinate: GeoCoordinate
    public let altitude: Altitude

    public init(coordinate: GeoCoordinate, altitude: Altitude) {
        self.coordinate = coordinate
        self.altitude = altitude
    }

    public var description: String {
        "<ObserverPosition redacted>"
    }

    public var debugDescription: String {
        description
    }
}

/// A true-geographic bearing normalized into `0 ..< 360` degrees.
public struct Bearing: Hashable, Sendable {
    public let degrees: Double

    public init(degrees: Double) throws {
        guard degrees.isFinite else {
            throw ThrowValidationError.nonFiniteValue(field: "bearing")
        }
        let remainder = degrees.truncatingRemainder(dividingBy: 360)
        self.degrees = remainder >= 0 ? remainder : remainder + 360
    }
}

public struct ElevationAngle: Hashable, Sendable {
    public let degrees: Double

    public init(degrees: Double) throws {
        guard degrees.isFinite else {
            throw ThrowValidationError.nonFiniteValue(field: "elevation")
        }
        guard (-90.0 ... 90.0).contains(degrees) else {
            throw ThrowValidationError.outOfRange(field: "elevation", closedRange: -90 ... 90)
        }
        self.degrees = degrees
    }
}

public struct NauticalMiles: Hashable, Comparable, Sendable {
    public let value: Double

    public init(value: Double) throws {
        guard value.isFinite else {
            throw ThrowValidationError.nonFiniteValue(field: "nauticalMiles")
        }
        guard (0.0 ... 20000.0).contains(value) else {
            throw ThrowValidationError.outOfRange(
                field: "nauticalMiles",
                closedRange: 0 ... 20000,
            )
        }
        self.value = value
    }

    public static func < (lhs: NauticalMiles, rhs: NauticalMiles) -> Bool {
        lhs.value < rhs.value
    }

    public var meters: Double {
        value * 1852
    }
}

public enum ProjectionMode: String, CaseIterable, Codable, Hashable, Sendable {
    case map
    case trueSky = "true-sky"
}

public struct MapViewport: Hashable, Sendable {
    public static let allowedRadius = 5.0 ... 240.0
    public static let defaultValue = try! MapViewport(radius: NauticalMiles(value: 50))

    public let radius: NauticalMiles

    public init(radius: NauticalMiles) throws {
        guard Self.allowedRadius.contains(radius.value), radius.value.rounded() == radius.value,
              Int(radius.value).isMultiple(of: 5)
        else {
            throw ThrowValidationError.outOfRange(
                field: "mapRadius",
                closedRange: Self.allowedRadius,
            )
        }
        self.radius = radius
    }
}

public struct SkyViewport: Hashable, Sendable {
    public static let allowedMinimumElevation = 0.0 ... 45.0
    public static let defaultValue = try! SkyViewport(
        minimumElevation: ElevationAngle(degrees: 10),
    )

    public let minimumElevation: ElevationAngle

    public init(minimumElevation: ElevationAngle) throws {
        guard Self.allowedMinimumElevation.contains(minimumElevation.degrees),
              minimumElevation.degrees.rounded() == minimumElevation.degrees
        else {
            throw ThrowValidationError.outOfRange(
                field: "minimumElevation",
                closedRange: Self.allowedMinimumElevation,
            )
        }
        self.minimumElevation = minimumElevation
    }
}

public enum ProjectionViewport: Hashable, Sendable {
    case map(MapViewport)
    case trueSky(SkyViewport)

    public var mode: ProjectionMode {
        switch self {
            case .map: .map
            case .trueSky: .trueSky
        }
    }
}

public struct PollingInterval: Hashable, Sendable {
    public static let allowedSeconds = 5 ... 300
    public static let defaultValue = try! PollingInterval(seconds: 10)

    public let seconds: Int

    public init(seconds: Int) throws {
        guard Self.allowedSeconds.contains(seconds) else {
            throw ThrowValidationError.outOfRange(
                field: "pollingInterval",
                closedRange: Double(Self.allowedSeconds.lowerBound) ...
                    Double(Self.allowedSeconds.upperBound),
            )
        }
        self.seconds = seconds
    }

    public var duration: Duration {
        .seconds(seconds)
    }
}
