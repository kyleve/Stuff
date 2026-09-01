import Foundation

public enum LayerID: String, CaseIterable, Hashable, Sendable {
    case geography
    case flights
    case stars
    case satellites
    case transitNetwork = "transit-network"
    case transitVehicles = "transit-vehicles"
}

public enum LayerMarkNamespace: String, Hashable, Sendable {
    case aircraft
    case airport
    case star
    case satellite
    case transitVehicle = "transit-vehicle"
}

public struct StarID: Hashable, Sendable {
    public let rawValue: String

    public init?(rawValue: String) {
        guard rawValue.isEmpty == false else { return nil }
        self.rawValue = rawValue
    }
}

public struct SatelliteID: Hashable, Sendable {
    public let rawValue: String

    public init?(rawValue: String) {
        guard rawValue.isEmpty == false else { return nil }
        self.rawValue = rawValue
    }
}

public struct TransitVehicleID: Hashable, Sendable {
    public let rawValue: String

    public init?(rawValue: String) {
        guard rawValue.isEmpty == false else { return nil }
        self.rawValue = rawValue
    }
}

/// A heterogeneous identity whose namespace prevents IDs from different layer
/// domains from colliding at the type-erasure boundary.
public enum LayerMarkID: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    case aircraft(AircraftID)
    case airport(AirportID)
    case star(StarID)
    case satellite(SatelliteID)
    case transitVehicle(TransitVehicleID)

    public var layerID: LayerID {
        switch self {
            case .aircraft, .airport: .flights
            case .star: .stars
            case .satellite: .satellites
            case .transitVehicle: .transitVehicles
        }
    }

    public var namespace: LayerMarkNamespace {
        switch self {
            case .aircraft: .aircraft
            case .airport: .airport
            case .star: .star
            case .satellite: .satellite
            case .transitVehicle: .transitVehicle
        }
    }

    public var rawValue: String {
        switch self {
            case let .aircraft(id): "\(id.kind.rawValue)/\(id.rawValue)"
            case let .airport(id): String(id.rawValue)
            case let .star(id): id.rawValue
            case let .satellite(id): id.rawValue
            case let .transitVehicle(id): id.rawValue
        }
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

public enum AvailableAltitudeQuality: String, Hashable, Sendable {
    case geometric
    case barometricApproximation
}

/// One valid altitude state for a geodetic projection anchor.
public enum GeodeticAltitude: Hashable, Sendable {
    case unavailable
    case available(Altitude, quality: AvailableAltitudeQuality)

    public var value: Altitude? {
        switch self {
            case .unavailable:
                nil
            case let .available(altitude, _):
                altitude
        }
    }

    public var quality: AvailableAltitudeQuality? {
        switch self {
            case .unavailable:
                nil
            case let .available(_, quality):
                quality
        }
    }
}

public struct GeodeticAnchor: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let coordinate: GeoCoordinate
    public let altitude: GeodeticAltitude

    public init(
        coordinate: GeoCoordinate,
        altitude: GeodeticAltitude,
    ) {
        self.coordinate = coordinate
        self.altitude = altitude
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
    public let horizontal: AircraftHorizontalMotion
    public let verticalRateFeetPerMinute: Double?

    public init(
        horizontal: AircraftHorizontalMotion,
        verticalRateFeetPerMinute: Double?,
    ) throws {
        if let verticalRateFeetPerMinute {
            guard verticalRateFeetPerMinute.isFinite else {
                throw ThrowValidationError.nonFiniteValue(field: "verticalRate")
            }
        }
        self.horizontal = horizontal
        self.verticalRateFeetPerMinute = verticalRateFeetPerMinute
    }

    public var groundTrack: Bearing? {
        horizontal.orientation
    }

    public var groundSpeedKnots: Double? {
        horizontal.availableValue?.speedKnots
    }

    public var turnRateDegreesPerSecond: Double? {
        horizontal.availableValue?.turnRateDegreesPerSecond
    }

    public var horizontalSource: AircraftHorizontalMotionSource? {
        horizontal.availableValue?.source
    }

    public static func available(
        track: Bearing,
        speedKnots: Double,
        verticalRateFeetPerMinute: Double?,
        turnRateDegreesPerSecond: Double?,
        source: AircraftHorizontalMotionSource,
    ) throws -> Self {
        try ProjectionVelocity(
            horizontal: .available(
                AvailableAircraftHorizontalMotion(
                    track: track,
                    speedKnots: speedKnots,
                    turnRateDegreesPerSecond: turnRateDegreesPerSecond,
                    source: source,
                ),
            ),
            verticalRateFeetPerMinute: verticalRateFeetPerMinute,
        )
    }

    public static func unavailable(
        orientation: Bearing?,
        verticalRateFeetPerMinute: Double?,
    ) throws -> Self {
        try ProjectionVelocity(
            horizontal: .unavailable(orientation: orientation),
            verticalRateFeetPerMinute: verticalRateFeetPerMinute,
        )
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

private func retainingLastMarkByIdentity<Mark>(
    _ marks: [Mark],
    identity: (Mark) -> LayerMarkID,
) -> [Mark] {
    var result: [Mark] = []
    result.reserveCapacity(marks.count)
    var indexByID: [LayerMarkID: Int] = [:]
    indexByID.reserveCapacity(marks.count)

    for mark in marks {
        let id = identity(mark)
        if let index = indexByID[id] {
            result[index] = mark
        } else {
            indexByID[id] = result.count
            result.append(mark)
        }
    }
    return result
}

/// A payload whose shape is fixed by its layer kind before type erasure.
public protocol ProjectionLayerPayload: Hashable, Sendable {
    static var empty: Self { get }
    var erasedContent: LayerFrameContent { get }
}

public struct ProjectionMarkLayerPayload: ProjectionLayerPayload {
    public static let empty = ProjectionMarkLayerPayload(marks: [])

    public let marks: [ProjectionMark]

    public init(marks: [ProjectionMark]) {
        self.marks = retainingLastMarkByIdentity(marks, identity: \.id)
    }

    public var erasedContent: LayerFrameContent {
        .marks(marks)
    }
}

public struct ProjectionLineLayerPayload: ProjectionLayerPayload {
    public static let empty = ProjectionLineLayerPayload(lines: [])

    public let lines: [ProjectionPolyline]

    public init(lines: [ProjectionPolyline]) {
        self.lines = lines
    }

    public var erasedContent: LayerFrameContent {
        .lines(lines)
    }
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
        let canonicalContent: LayerFrameContent = switch content {
            case let .marks(marks): .marks(retainingLastMarkByIdentity(marks, identity: \.id))
            case let .lines(lines): .lines(lines)
        }
        if case let .marks(marks) = canonicalContent {
            precondition(marks.allSatisfy { $0.id.layerID == layerID })
        }
        self.layerID = layerID
        self.observedAt = observedAt
        self.content = canonicalContent
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

/// A compile-time identity for one semantic projection layer.
public protocol ProjectionLayerKind: Sendable {
    associatedtype Payload: ProjectionLayerPayload

    static var id: LayerID { get }
    static var supportedModes: Set<ProjectionMode> { get }
}

public enum GeographyLayerKind: ProjectionLayerKind {
    public typealias Payload = ProjectionLineLayerPayload
    public static let id = LayerID.geography
    public static let supportedModes: Set<ProjectionMode> = [.map]
}

public enum FlightsLayerKind: ProjectionLayerKind {
    public typealias Payload = ProjectionMarkLayerPayload
    public static let id = LayerID.flights
    public static let supportedModes: Set<ProjectionMode> = [.map, .trueSky]
}

public enum StarsLayerKind: ProjectionLayerKind {
    public typealias Payload = ProjectionMarkLayerPayload
    public static let id = LayerID.stars
    public static let supportedModes: Set<ProjectionMode> = [.trueSky]
}

public enum SatellitesLayerKind: ProjectionLayerKind {
    public typealias Payload = ProjectionMarkLayerPayload
    public static let id = LayerID.satellites
    public static let supportedModes: Set<ProjectionMode> = [.map, .trueSky]
}

public enum TransitNetworkLayerKind: ProjectionLayerKind {
    public typealias Payload = ProjectionLineLayerPayload
    public static let id = LayerID.transitNetwork
    public static let supportedModes: Set<ProjectionMode> = [.map]
}

public enum TransitVehiclesLayerKind: ProjectionLayerKind {
    public typealias Payload = ProjectionMarkLayerPayload
    public static let id = LayerID.transitVehicles
    public static let supportedModes: Set<ProjectionMode> = [.map]
}

/// A semantic frame whose layer identity is fixed by its generic argument.
public struct ProjectionLayerFrame<Layer: ProjectionLayerKind>: Hashable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible
{
    public let observedAt: Date
    public let payload: Layer.Payload

    public init(observedAt: Date, payload: Layer.Payload) {
        self.observedAt = observedAt
        self.payload = payload
    }

    public var layerID: LayerID {
        Layer.id
    }

    public var erased: LayerFrame {
        LayerFrame(
            layerID: Layer.id,
            observedAt: observedAt,
            content: payload.erasedContent,
        )
    }

    public var description: String {
        erased.description
    }

    public var debugDescription: String {
        erased.debugDescription
    }
}

extension ProjectionLayerFrame where Layer.Payload == ProjectionMarkLayerPayload {
    public init(observedAt: Date, marks: [ProjectionMark]) {
        self.init(observedAt: observedAt, payload: ProjectionMarkLayerPayload(marks: marks))
    }

    public var marks: [ProjectionMark] {
        payload.marks
    }
}

extension ProjectionLayerFrame where Layer.Payload == ProjectionLineLayerPayload {
    public init(observedAt: Date, lines: [ProjectionPolyline]) {
        self.init(observedAt: observedAt, payload: ProjectionLineLayerPayload(lines: lines))
    }

    public var lines: [ProjectionPolyline] {
        payload.lines
    }

    public var geographicLines: [GeographicPolyline] {
        lines
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
        let canonicalContent: ProjectedLayerContent = switch content {
            case let .marks(marks): .marks(retainingLastMarkByIdentity(marks, identity: \.id))
            case let .lines(lines): .lines(lines)
        }
        if case let .marks(marks) = canonicalContent {
            precondition(marks.allSatisfy { $0.id.layerID == id })
        }
        self.id = id
        self.zOrder = zOrder
        self.opacity = opacity
        self.content = canonicalContent
    }

    public var marks: [ProjectedMark] {
        if case let .marks(marks) = content { marks } else { [] }
    }

    public var lines: ProjectedLineCollection? {
        if case let .lines(lines) = content { lines } else { nil }
    }
}

/// The semantic layers that can participate in Air & Space.
public struct AirAndSpaceExperienceFrame: Hashable, Sendable {
    public static let empty = AirAndSpaceExperienceFrame(
        geography: nil,
        flights: nil,
        stars: nil,
        satellites: nil,
    )

    public let geography: ProjectionLayerFrame<GeographyLayerKind>?
    public let flights: ProjectionLayerFrame<FlightsLayerKind>?
    public let stars: ProjectionLayerFrame<StarsLayerKind>?
    public let satellites: ProjectionLayerFrame<SatellitesLayerKind>?

    public init(
        geography: ProjectionLayerFrame<GeographyLayerKind>?,
        flights: ProjectionLayerFrame<FlightsLayerKind>?,
        stars: ProjectionLayerFrame<StarsLayerKind>?,
        satellites: ProjectionLayerFrame<SatellitesLayerKind>?,
    ) {
        self.geography = geography
        self.flights = flights
        self.stars = stars
        self.satellites = satellites
    }

    public var layers: [LayerFrame] {
        [geography?.erased, flights?.erased, stars?.erased, satellites?.erased].compactMap(\.self)
    }
}

/// The semantic layers that can participate in Transit.
public struct TransitExperienceFrame: Hashable, Sendable {
    public static let empty = TransitExperienceFrame(
        geography: nil,
        network: nil,
        vehicles: nil,
    )

    public let geography: ProjectionLayerFrame<GeographyLayerKind>?
    public let network: ProjectionLayerFrame<TransitNetworkLayerKind>?
    public let vehicles: ProjectionLayerFrame<TransitVehiclesLayerKind>?

    public init(
        geography: ProjectionLayerFrame<GeographyLayerKind>?,
        network: ProjectionLayerFrame<TransitNetworkLayerKind>?,
        vehicles: ProjectionLayerFrame<TransitVehiclesLayerKind>?,
    ) {
        self.geography = geography
        self.network = network
        self.vehicles = vehicles
    }

    public var layers: [LayerFrame] {
        [geography?.erased, network?.erased, vehicles?.erased].compactMap(\.self)
    }
}

/// One experience's semantic layers before geometry projection. Each case accepts only
/// that experience's compile-time layer set.
public enum ProjectionExperienceFrame: Hashable, Sendable {
    case airAndSpace(AirAndSpaceExperienceFrame)
    case transit(TransitExperienceFrame)

    public static func empty(for id: ProjectionExperienceID) -> Self {
        switch id {
            case .airAndSpace:
                .airAndSpace(.empty)
            case .transit:
                .transit(.empty)
            default:
                preconditionFailure("A test-only experience must supply its own semantic frame")
        }
    }

    public var experienceID: ProjectionExperienceID {
        switch self {
            case .airAndSpace: .airAndSpace
            case .transit: .transit
        }
    }

    public var layers: [LayerFrame] {
        switch self {
            case let .airAndSpace(frame): frame.layers
            case let .transit(frame): frame.layers
        }
    }
}

public enum GeographyLayerVisibility: Hashable, Sendable {
    case hidden
    case visible
}

/// Air & Space's projection choices. Geography is spellable only for Map.
public enum AirAndSpaceProjectionViewport: Hashable, Sendable {
    case map(viewport: MapViewport, geography: GeographyLayerVisibility)
    case trueSky(viewport: SkyViewport)

    public var viewport: ProjectionViewport {
        switch self {
            case let .map(viewport, _): .map(viewport)
            case let .trueSky(viewport): .trueSky(viewport)
        }
    }

    public var requestsGeography: Bool {
        switch self {
            case let .map(_, geography): geography == .visible
            case .trueSky: false
        }
    }
}

/// A projection request that makes experience membership and supported modes
/// unrepresentable as mismatched parallel values.
public enum ProjectionExperienceInput: Hashable, Sendable {
    case airAndSpace(
        frame: AirAndSpaceExperienceFrame,
        viewport: AirAndSpaceProjectionViewport,
    )
    case transit(
        frame: TransitExperienceFrame,
        viewport: MapViewport,
        geography: GeographyLayerVisibility,
    )

    public var experienceFrame: ProjectionExperienceFrame {
        switch self {
            case let .airAndSpace(frame, _): .airAndSpace(frame)
            case let .transit(frame, _, _): .transit(frame)
        }
    }

    public var viewport: ProjectionViewport {
        switch self {
            case let .airAndSpace(_, viewport): viewport.viewport
            case let .transit(_, viewport, _): .map(viewport)
        }
    }

    public var requestsGeography: Bool {
        switch self {
            case let .airAndSpace(_, viewport): viewport.requestsGeography
            case let .transit(_, _, geography): geography == .visible
        }
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
        switch id {
            case .geography: 0
            case .stars: 10
            case .transitNetwork: 20
            case .satellites: 50
            case .flights, .transitVehicles: 100
        }
    }
}
