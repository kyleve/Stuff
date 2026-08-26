import Foundation

public struct LayerID: Hashable, Sendable {
    public static let geography = LayerID(rawValue: "geography")
    public static let flights = LayerID(rawValue: "flights")
    public static let stars = LayerID(rawValue: "stars")
    public static let satellites = LayerID(rawValue: "satellites")
    public static let transitNetwork = LayerID(rawValue: "transit-network")
    public static let transitVehicles = LayerID(rawValue: "transit-vehicles")

    public let rawValue: String

    public init(rawValue: String) {
        precondition(rawValue.isEmpty == false, "A layer ID must not be empty")
        self.rawValue = rawValue
    }
}

public enum LayerMarkNamespace: String, Hashable, Sendable {
    case aircraft
    case airport
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
    case aircraft(AircraftGlyphDescriptor)
    case airport(AirportGlyphDescriptor)
    case star
    case satellite
}

public enum ProjectionLabelRole: Hashable, Sendable {
    case headline
    case detail
}

public struct ProjectionLabel: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let primary: String
    public let primaryRole: ProjectionLabelRole
    public let secondary: String?

    public init(
        primary: String,
        primaryRole: ProjectionLabelRole,
        secondary: String?,
    ) {
        precondition(primary.isEmpty == false, "A projection label must have primary text")
        self.primary = primary
        self.primaryRole = primaryRole
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
    public let turnRateDegreesPerSecond: Double?
    public let horizontalSource: AircraftHorizontalMotionSource

    public init(
        groundTrack: Bearing?,
        groundSpeedKnots: Double?,
        verticalRateFeetPerMinute: Double?,
        turnRateDegreesPerSecond: Double?,
        horizontalSource: AircraftHorizontalMotionSource,
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
        if let turnRateDegreesPerSecond {
            guard turnRateDegreesPerSecond.isFinite else {
                throw ThrowValidationError.nonFiniteValue(field: "turnRate")
            }
            guard (-3 ... 3).contains(turnRateDegreesPerSecond) else {
                throw ThrowValidationError.outOfRange(
                    field: "turnRate",
                    closedRange: -3 ... 3,
                )
            }
        }
        precondition(
            horizontalSource == .unavailable ||
                (groundTrack != nil && groundSpeedKnots != nil),
            "Available horizontal motion requires both track and speed",
        )
        precondition(
            turnRateDegreesPerSecond == nil ||
                (groundTrack != nil && groundSpeedKnots != nil),
            "Turn-rate prediction requires horizontal motion",
        )
        self.groundTrack = groundTrack
        self.groundSpeedKnots = groundSpeedKnots
        self.verticalRateFeetPerMinute = verticalRateFeetPerMinute
        self.turnRateDegreesPerSecond = turnRateDegreesPerSecond
        self.horizontalSource = horizontalSource
    }
}

public enum MarkAvailability: Hashable, Sendable {
    case current
    case retrying(since: Date)
}

public struct MarkFreshness: Hashable, Sendable {
    public let positionObservedAt: Date
    public let fetchedAt: Date
    public let availability: MarkAvailability

    public init(
        positionObservedAt: Date,
        fetchedAt: Date,
        availability: MarkAvailability,
    ) {
        self.positionObservedAt = positionObservedAt
        self.fetchedAt = fetchedAt
        self.availability = availability
    }
}

public enum ProjectionProminence: Hashable, Sendable {
    case primary
    case secondary
}

public struct ProjectionMark: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let id: LayerMarkID
    public let anchor: ProjectionAnchor
    public let glyph: ProjectionGlyph
    public let label: ProjectionLabel?
    public let prominence: ProjectionProminence
    public let velocity: ProjectionVelocity?
    public let freshness: MarkFreshness

    public init(
        id: LayerMarkID,
        anchor: ProjectionAnchor,
        glyph: ProjectionGlyph,
        label: ProjectionLabel?,
        prominence: ProjectionProminence,
        velocity: ProjectionVelocity?,
        freshness: MarkFreshness,
    ) {
        self.id = id
        self.anchor = anchor
        self.glyph = glyph
        self.label = label
        self.prominence = prominence
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
    case lines([ProjectionPolyline])
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

    public var lines: [ProjectionPolyline] {
        if case let .lines(lines) = content { lines } else { [] }
    }

    public var geographicLines: [GeographicPolyline] {
        lines
    }

    public var description: String {
        "<LayerFrame layer=\(layerID.rawValue) marks=\(marks.count) lines=\(lines.count)>"
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
    /// Zero for primary marks and one for fully secondary marks. Intermediate
    /// values exist only while presentation interpolates between the states.
    public let secondaryProminence: Double
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
        secondaryProminence: Double,
        orientationDegrees: Double?,
        opacity: Double,
        labelOpacity: Double,
        altitudeIsApproximate: Bool,
    ) {
        precondition((0 ... 1).contains(opacity))
        precondition((0 ... 1).contains(labelOpacity))
        precondition((0 ... 1).contains(secondaryProminence))
        self.id = id
        self.point = point
        self.range = range
        self.glyph = glyph
        self.label = label
        self.secondaryProminence = secondaryProminence
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

public struct ProjectedLineSegment: Hashable, Sendable {
    public let styleID: ProjectionLineStyleID
    public let start: ProjectionPoint
    public let end: ProjectionPoint
    /// Whether the renderer must move to `start` instead of continuing the
    /// current path. This preserves joins and dash phase within a polyline.
    public let startsNewSubpath: Bool

    public init(
        styleID: ProjectionLineStyleID,
        start: ProjectionPoint,
        end: ProjectionPoint,
        startsNewSubpath: Bool,
    ) {
        self.styleID = styleID
        self.start = start
        self.end = end
        self.startsNewSubpath = startsNewSubpath
    }

    public init(
        kind: GeographyLineKind,
        start: ProjectionPoint,
        end: ProjectionPoint,
        startsNewSubpath: Bool,
    ) {
        self.init(
            styleID: ProjectionLineStyleID(geographyKind: kind),
            start: start,
            end: end,
            startsNewSubpath: startsNewSubpath,
        )
    }

    public var kind: GeographyLineKind {
        guard let kind = styleID.geographyKind else {
            preconditionFailure("A non-geographic line style has no Geography kind")
        }
        return kind
    }
}

public typealias ProjectedGeographySegment = ProjectedLineSegment

/// Identifies one cached static-line projection for UI path reuse.
public struct ProjectionLineRevisionID: Hashable, Sendable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }
}

public typealias GeographyProjectionID = ProjectionLineRevisionID

/// Cached normalized line segments and their stable render identity.
public struct ProjectedLineCollection: Hashable, Sendable {
    public let id: ProjectionLineRevisionID
    public let segments: [ProjectedLineSegment]

    public init(id: ProjectionLineRevisionID, segments: [ProjectedLineSegment]) {
        self.id = id
        self.segments = segments
    }
}

public typealias ProjectedGeography = ProjectedLineCollection

public enum ProjectedLayerContent: Hashable, Sendable {
    case marks([ProjectedMark])
    case lines(ProjectedLineCollection)
}

public struct ProjectedLayer: Identifiable, Hashable, Sendable {
    public let id: LayerID
    public let zOrder: Int
    public let opacity: Double
    public let content: ProjectedLayerContent

    public init(
        id: LayerID,
        zOrder: Int,
        opacity: Double,
        content: ProjectedLayerContent,
    ) {
        precondition((0 ... 1).contains(opacity))
        if case let .marks(marks) = content {
            precondition(marks.allSatisfy { $0.id.layerID == id })
        }
        self.id = id
        self.zOrder = zOrder
        self.opacity = opacity
        self.content = content
    }

    public var marks: [ProjectedMark] {
        if case let .marks(marks) = content { marks } else { [] }
    }

    public var lines: ProjectedLineCollection? {
        if case let .lines(lines) = content { lines } else { nil }
    }
}

/// One experience's semantic layers before geometry projection.
public struct ProjectionExperienceFrame: Hashable, Sendable {
    public let experienceID: ProjectionExperienceID
    public let layers: [LayerFrame]

    public init(experienceID: ProjectionExperienceID, layers: [LayerFrame]) {
        precondition(Set(layers.map(\.layerID)).count == layers.count)
        self.experienceID = experienceID
        self.layers = layers
    }
}

public struct ProjectionFrame: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let experienceID: ProjectionExperienceID
    public let mode: ProjectionMode
    public let generatedAt: Date
    public let layers: [ProjectedLayer]

    public init(
        experienceID: ProjectionExperienceID,
        mode: ProjectionMode,
        generatedAt: Date,
        layers: [ProjectedLayer],
    ) {
        precondition(Set(layers.map(\.id)).count == layers.count)
        self.experienceID = experienceID
        self.mode = mode
        self.generatedAt = generatedAt
        self.layers = layers.sorted { lhs, rhs in
            if lhs.zOrder == rhs.zOrder {
                lhs.id.rawValue < rhs.id.rawValue
            } else {
                lhs.zOrder < rhs.zOrder
            }
        }
    }

    /// Compatibility initializer while fixtures move to generic projected layers.
    public init(
        mode: ProjectionMode,
        generatedAt: Date,
        geography: ProjectedGeography?,
        geographyOpacity: Double,
        marks: [ProjectedMark],
    ) {
        precondition((0 ... 1).contains(geographyOpacity))
        var layers: [ProjectedLayer] = []
        if let geography {
            layers.append(
                ProjectedLayer(
                    id: .geography,
                    zOrder: 0,
                    opacity: geographyOpacity,
                    content: .lines(geography),
                ),
            )
        }
        let marksByLayer = Dictionary(grouping: marks, by: { $0.id.layerID })
        layers.append(contentsOf: marksByLayer.map { id, marks in
            ProjectedLayer(
                id: id,
                zOrder: Self.standardZOrder(for: id),
                opacity: 1,
                content: .marks(marks),
            )
        })
        self.init(
            experienceID: .airAndSpace,
            mode: mode,
            generatedAt: generatedAt,
            layers: layers,
        )
    }

    public var marks: [ProjectedMark] {
        layers.flatMap(\.marks)
    }

    public var geography: ProjectedGeography? {
        layers.first { $0.id == .geography }?.lines
    }

    public var geographyOpacity: Double {
        layers.first { $0.id == .geography }?.opacity ?? 1
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

    public func replacingMarks(_ marks: [ProjectedMark]) -> ProjectionFrame {
        let marksByLayer = Dictionary(grouping: marks, by: { $0.id.layerID })
        var replacedLayerIDs: Set<LayerID> = []
        var newLayers = layers.map { layer in
            guard case .marks = layer.content else { return layer }
            replacedLayerIDs.insert(layer.id)
            return ProjectedLayer(
                id: layer.id,
                zOrder: layer.zOrder,
                opacity: layer.opacity,
                content: .marks(marksByLayer[layer.id] ?? []),
            )
        }
        for (id, layerMarks) in marksByLayer where replacedLayerIDs.contains(id) == false {
            newLayers.append(
                ProjectedLayer(
                    id: id,
                    zOrder: Self.standardZOrder(for: id),
                    opacity: 1,
                    content: .marks(layerMarks),
                ),
            )
        }
        return ProjectionFrame(
            experienceID: experienceID,
            mode: mode,
            generatedAt: generatedAt,
            layers: newLayers,
        )
    }

    public func replacingLineLayer(
        id: LayerID,
        lines: ProjectedLineCollection?,
        opacity: Double,
    ) -> ProjectionFrame {
        precondition((0 ... 1).contains(opacity))
        var replaced = false
        var newLayers = layers.compactMap { layer -> ProjectedLayer? in
            guard layer.id == id else { return layer }
            replaced = true
            guard let lines else { return nil }
            return ProjectedLayer(
                id: id,
                zOrder: layer.zOrder,
                opacity: opacity,
                content: .lines(lines),
            )
        }
        if replaced == false, let lines {
            newLayers.append(
                ProjectedLayer(
                    id: id,
                    zOrder: Self.standardZOrder(for: id),
                    opacity: opacity,
                    content: .lines(lines),
                ),
            )
        }
        return ProjectionFrame(
            experienceID: experienceID,
            mode: mode,
            generatedAt: generatedAt,
            layers: newLayers,
        )
    }

    public func replacingLineLayers(_ lineLayers: [ProjectedLayer]) -> ProjectionFrame {
        precondition(lineLayers.allSatisfy { layer in
            if case .lines = layer.content { true } else { false }
        })
        precondition(Set(lineLayers.map(\.id)).count == lineLayers.count)
        return ProjectionFrame(
            experienceID: experienceID,
            mode: mode,
            generatedAt: generatedAt,
            layers: layers.filter { layer in
                if case .lines = layer.content { false } else { true }
            } + lineLayers,
        )
    }

    private static func standardZOrder(for id: LayerID) -> Int {
        if id == .geography { return 0 }
        if id == .stars { return 10 }
        if id == .transitNetwork { return 20 }
        if id == .satellites { return 50 }
        return 100
    }
}
