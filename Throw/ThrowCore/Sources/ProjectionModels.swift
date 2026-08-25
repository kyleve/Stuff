import Foundation

public struct LayerID: Hashable, Sendable {
    public static let geography = LayerID(rawValue: "geography")
    public static let flights = LayerID(rawValue: "flights")
    public static let stars = LayerID(rawValue: "stars")
    public static let satellites = LayerID(rawValue: "satellites")

    public let rawValue: String

    public init(rawValue: String) {
        precondition(rawValue.isEmpty == false, "A layer ID must not be empty")
        self.rawValue = rawValue
    }
}

public enum LayerMarkNamespace: String, Hashable, Sendable {
    case aircraft
    case star
    case satellite
}

/// A heterogeneous identity whose namespace prevents IDs from different layer
/// domains from colliding at the type-erasure boundary.
public struct LayerMarkID: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let layerID: LayerID
    public let namespace: LayerMarkNamespace
    public let rawValue: String

    public init(layerID: LayerID, namespace: LayerMarkNamespace, rawValue: String) {
        precondition(rawValue.isEmpty == false, "A layer-mark ID must not be empty")
        self.layerID = layerID
        self.namespace = namespace
        self.rawValue = rawValue
    }

    public var description: String {
        "<LayerMarkID layer=\(layerID.rawValue) namespace=\(namespace.rawValue) value=<redacted>>"
    }

    public var debugDescription: String {
        description
    }
}

public enum ScreenRotation: Int, CaseIterable, Codable, Hashable, Sendable {
    case degrees0 = 0
    case degrees90 = 90
    case degrees180 = 180
    case degrees270 = 270
}

public struct ProjectionCalibration: Hashable, Sendable {
    public static let allowedSafeInsetFraction = 0.0 ... 0.2
    public static let defaultValue = try! ProjectionCalibration(
        screenTopBearing: Bearing(degrees: 0),
        rotation: .degrees0,
        flipHorizontal: false,
        flipVertical: false,
        safeInsetFraction: 0.05,
        verifiedOnExternalDisplay: false,
    )

    public let screenTopBearing: Bearing
    public let rotation: ScreenRotation
    public let flipHorizontal: Bool
    public let flipVertical: Bool
    public let safeInsetFraction: Double
    public let verifiedOnExternalDisplay: Bool

    public init(
        screenTopBearing: Bearing,
        rotation: ScreenRotation,
        flipHorizontal: Bool,
        flipVertical: Bool,
        safeInsetFraction: Double,
        verifiedOnExternalDisplay: Bool,
    ) throws {
        guard safeInsetFraction.isFinite else {
            throw ThrowValidationError.nonFiniteValue(field: "safeInset")
        }
        guard Self.allowedSafeInsetFraction.contains(safeInsetFraction) else {
            throw ThrowValidationError.outOfRange(
                field: "safeInset",
                closedRange: Self.allowedSafeInsetFraction,
            )
        }
        self.screenTopBearing = screenTopBearing
        self.rotation = rotation
        self.flipHorizontal = flipHorizontal
        self.flipVertical = flipVertical
        self.safeInsetFraction = safeInsetFraction
        self.verifiedOnExternalDisplay = verifiedOnExternalDisplay
    }
}

public enum AltitudeQuality: String, Hashable, Sendable {
    case geometric
    case barometricApproximation
    case unavailable
}

public struct GeodeticAnchor: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let coordinate: GeoCoordinate
    public let altitude: Altitude?
    public let altitudeQuality: AltitudeQuality

    public init(
        coordinate: GeoCoordinate,
        altitude: Altitude?,
        altitudeQuality: AltitudeQuality,
    ) {
        precondition(
            (altitude == nil) == (altitudeQuality == .unavailable),
            "Altitude availability and quality must agree",
        )
        self.coordinate = coordinate
        self.altitude = altitude
        self.altitudeQuality = altitudeQuality
    }

    public var description: String {
        "<GeodeticAnchor coordinate=<redacted>>"
    }

    public var debugDescription: String {
        description
    }
}

public struct HorizontalAnchor: Hashable, Sendable {
    public let azimuth: Bearing
    public let elevation: ElevationAngle

    public init(azimuth: Bearing, elevation: ElevationAngle) {
        self.azimuth = azimuth
        self.elevation = elevation
    }
}

public enum ProjectionAnchor: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    case geodetic(GeodeticAnchor)
    case horizontal(HorizontalAnchor)

    public var description: String {
        "<ProjectionAnchor redacted>"
    }

    public var debugDescription: String {
        description
    }
}

public enum ProjectionGlyph: Hashable, Sendable {
    case aircraft(isGrounded: Bool)
    case star
    case satellite
}

public struct ProjectionLabel: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let primary: String
    public let secondary: String?

    public init(primary: String, secondary: String?) {
        precondition(primary.isEmpty == false, "A projection label must have primary text")
        self.primary = primary
        self.secondary = secondary
    }

    public var description: String {
        "<ProjectionLabel redacted>"
    }

    public var debugDescription: String {
        description
    }
}

public struct ProjectionVelocity: Hashable, Sendable {
    public let groundTrack: Bearing?
    public let groundSpeedKnots: Double?
    public let verticalRateFeetPerMinute: Double?

    public init(
        groundTrack: Bearing?,
        groundSpeedKnots: Double?,
        verticalRateFeetPerMinute: Double?,
    ) throws {
        if let groundSpeedKnots {
            guard groundSpeedKnots.isFinite, (0 ... 2000).contains(groundSpeedKnots) else {
                throw ThrowValidationError.outOfRange(
                    field: "groundSpeed",
                    closedRange: 0 ... 2000,
                )
            }
        }
        if let verticalRateFeetPerMinute {
            guard verticalRateFeetPerMinute.isFinite else {
                throw ThrowValidationError.nonFiniteValue(field: "verticalRate")
            }
        }
        self.groundTrack = groundTrack
        self.groundSpeedKnots = groundSpeedKnots
        self.verticalRateFeetPerMinute = verticalRateFeetPerMinute
    }
}

public struct MarkFreshness: Hashable, Sendable {
    public let positionObservedAt: Date
    public let fetchedAt: Date

    public init(positionObservedAt: Date, fetchedAt: Date) {
        self.positionObservedAt = positionObservedAt
        self.fetchedAt = fetchedAt
    }
}

public struct ProjectionMark: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let id: LayerMarkID
    public let anchor: ProjectionAnchor
    public let glyph: ProjectionGlyph
    public let label: ProjectionLabel?
    public let velocity: ProjectionVelocity?
    public let freshness: MarkFreshness

    public init(
        id: LayerMarkID,
        anchor: ProjectionAnchor,
        glyph: ProjectionGlyph,
        label: ProjectionLabel?,
        velocity: ProjectionVelocity?,
        freshness: MarkFreshness,
    ) {
        self.id = id
        self.anchor = anchor
        self.glyph = glyph
        self.label = label
        self.velocity = velocity
        self.freshness = freshness
    }

    public var description: String {
        "<ProjectionMark redacted>"
    }

    public var debugDescription: String {
        description
    }
}

/// One semantic payload for a layer frame; layers cannot mix mark and line data.
public enum LayerFrameContent: Hashable, Sendable {
    case marks([ProjectionMark])
    case geographicLines([GeographicPolyline])
}

public struct LayerFrame: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let layerID: LayerID
    public let observedAt: Date
    public let content: LayerFrameContent

    public init(
        layerID: LayerID,
        observedAt: Date,
        content: LayerFrameContent,
    ) {
        if case let .marks(marks) = content {
            precondition(marks.allSatisfy { $0.id.layerID == layerID })
        }
        self.layerID = layerID
        self.observedAt = observedAt
        self.content = content
    }

    public var marks: [ProjectionMark] {
        if case let .marks(marks) = content { marks } else { [] }
    }

    public var geographicLines: [GeographicPolyline] {
        if case let .geographicLines(lines) = content { lines } else { [] }
    }

    public var description: String {
        "<LayerFrame layer=\(layerID.rawValue) marks=\(marks.count) lines=\(geographicLines.count)>"
    }

    public var debugDescription: String {
        description
    }
}

/// A unit square centered on `(0.5, 0.5)` after calibration and safe inset.
public struct ProjectionPoint: Hashable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        precondition(x.isFinite && y.isFinite)
        self.x = x
        self.y = y
    }
}

public struct ProjectedMark: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let id: LayerMarkID
    public let point: ProjectionPoint
    /// Ground range in Map and slant range in True Sky. Non-geodetic layers may omit it.
    public let range: NauticalMiles?
    public let glyph: ProjectionGlyph
    public let label: ProjectionLabel?
    public let orientationDegrees: Double?
    public let opacity: Double
    public let labelOpacity: Double
    public let altitudeIsApproximate: Bool

    public init(
        id: LayerMarkID,
        point: ProjectionPoint,
        range: NauticalMiles?,
        glyph: ProjectionGlyph,
        label: ProjectionLabel?,
        orientationDegrees: Double?,
        opacity: Double,
        labelOpacity: Double,
        altitudeIsApproximate: Bool,
    ) {
        precondition((0 ... 1).contains(opacity))
        precondition((0 ... 1).contains(labelOpacity))
        self.id = id
        self.point = point
        self.range = range
        self.glyph = glyph
        self.label = label
        self.orientationDegrees = orientationDegrees
        self.opacity = opacity
        self.labelOpacity = labelOpacity
        self.altitudeIsApproximate = altitudeIsApproximate
    }

    public var description: String {
        "<ProjectedMark redacted>"
    }

    public var debugDescription: String {
        description
    }
}

public struct ProjectedGeographySegment: Hashable, Sendable {
    public let kind: GeographyLineKind
    public let start: ProjectionPoint
    public let end: ProjectionPoint
    /// Whether the renderer must move to `start` instead of continuing the
    /// current path. This preserves joins and dash phase within a polyline.
    public let startsNewSubpath: Bool

    public init(
        kind: GeographyLineKind,
        start: ProjectionPoint,
        end: ProjectionPoint,
        startsNewSubpath: Bool,
    ) {
        self.kind = kind
        self.start = start
        self.end = end
        self.startsNewSubpath = startsNewSubpath
    }
}

/// Identifies one cached geography projection for UI path reuse.
public struct GeographyProjectionID: Hashable, Sendable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }
}

/// Cached normalized geography segments and their stable render identity.
public struct ProjectedGeography: Hashable, Sendable {
    public let id: GeographyProjectionID
    public let segments: [ProjectedGeographySegment]

    public init(id: GeographyProjectionID, segments: [ProjectedGeographySegment]) {
        self.id = id
        self.segments = segments
    }
}

public struct ProjectionFrame: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let mode: ProjectionMode
    public let generatedAt: Date
    public let geography: ProjectedGeography?
    public let geographyOpacity: Double
    public let marks: [ProjectedMark]

    public init(
        mode: ProjectionMode,
        generatedAt: Date,
        geography: ProjectedGeography?,
        geographyOpacity: Double,
        marks: [ProjectedMark],
    ) {
        precondition((0 ... 1).contains(geographyOpacity))
        self.mode = mode
        self.generatedAt = generatedAt
        self.geography = geography
        self.geographyOpacity = geographyOpacity
        self.marks = marks
    }

    public var geographySegments: [ProjectedGeographySegment] {
        geography?.segments ?? []
    }

    public var visibleAircraftCount: Int {
        marks.count { mark in
            if case .aircraft = mark.glyph { true } else { false }
        }
    }

    public var description: String {
        "<ProjectionFrame mode=\(mode.rawValue) marks=\(marks.count) geography=\(geographySegments.count)>"
    }

    public var debugDescription: String {
        description
    }
}
