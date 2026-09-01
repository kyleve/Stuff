import Foundation

public enum LayerID: String, CaseIterable, Hashable, Sendable {
    case geography
    case flights
    case stars
    case satellites
    case transitNetwork = "transit-network"
    case transitVehicles = "transit-vehicles"

    /// The fixed back-to-front order for projection rendering.
    public var projectionZOrder: Int {
        switch self {
            case .geography: 0
            case .stars: 10
            case .transitNetwork: 20
            case .satellites: 50
            case .flights, .transitVehicles: 100
        }
    }
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

    public func replacingScreenTopBearing(_ screenTopBearing: Bearing) -> Self {
        Self(
            validatedScreenTopBearing: screenTopBearing,
            rotation: rotation,
            flipHorizontal: flipHorizontal,
            flipVertical: flipVertical,
            safeInsetFraction: safeInsetFraction,
            verifiedOnExternalDisplay: verifiedOnExternalDisplay,
        )
    }

    public func replacingRotation(_ rotation: ScreenRotation) -> Self {
        Self(
            validatedScreenTopBearing: screenTopBearing,
            rotation: rotation,
            flipHorizontal: flipHorizontal,
            flipVertical: flipVertical,
            safeInsetFraction: safeInsetFraction,
            verifiedOnExternalDisplay: verifiedOnExternalDisplay,
        )
    }

    public func replacingFlipHorizontal(_ flipHorizontal: Bool) -> Self {
        Self(
            validatedScreenTopBearing: screenTopBearing,
            rotation: rotation,
            flipHorizontal: flipHorizontal,
            flipVertical: flipVertical,
            safeInsetFraction: safeInsetFraction,
            verifiedOnExternalDisplay: verifiedOnExternalDisplay,
        )
    }

    public func replacingFlipVertical(_ flipVertical: Bool) -> Self {
        Self(
            validatedScreenTopBearing: screenTopBearing,
            rotation: rotation,
            flipHorizontal: flipHorizontal,
            flipVertical: flipVertical,
            safeInsetFraction: safeInsetFraction,
            verifiedOnExternalDisplay: verifiedOnExternalDisplay,
        )
    }

    public func replacingSafeInsetFraction(_ safeInsetFraction: Double) throws -> Self {
        try Self(
            screenTopBearing: screenTopBearing,
            rotation: rotation,
            flipHorizontal: flipHorizontal,
            flipVertical: flipVertical,
            safeInsetFraction: safeInsetFraction,
            verifiedOnExternalDisplay: verifiedOnExternalDisplay,
        )
    }

    public func replacingVerifiedOnExternalDisplay(
        _ verifiedOnExternalDisplay: Bool,
    ) -> Self {
        Self(
            validatedScreenTopBearing: screenTopBearing,
            rotation: rotation,
            flipHorizontal: flipHorizontal,
            flipVertical: flipVertical,
            safeInsetFraction: safeInsetFraction,
            verifiedOnExternalDisplay: verifiedOnExternalDisplay,
        )
    }

    private init(
        validatedScreenTopBearing screenTopBearing: Bearing,
        rotation: ScreenRotation,
        flipHorizontal: Bool,
        flipVertical: Bool,
        safeInsetFraction: Double,
        verifiedOnExternalDisplay: Bool,
    ) {
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
    associatedtype Projected: ProjectedLayerPayload

    static var empty: Self { get }
    var erasedContent: LayerFrameContent { get }
}

public struct ProjectionMarkLayerPayload: ProjectionLayerPayload {
    public typealias Projected = ProjectedMarkLayerPayload
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
    public typealias Projected = ProjectedLineLayerPayload
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

extension ProjectionLayerKind {
    public static var zOrder: Int {
        id.projectionZOrder
    }
}

/// A layer whose semantic and projected forms both contain marks.
public protocol ProjectionMarkLayerKind: ProjectionLayerKind
    where Payload == ProjectionMarkLayerPayload {}

/// A layer whose semantic and projected forms both contain lines.
public protocol ProjectionLineLayerKind: ProjectionLayerKind
    where Payload == ProjectionLineLayerPayload {}

public enum GeographyLayerKind: ProjectionLineLayerKind {
    public typealias Payload = ProjectionLineLayerPayload
    public static let id = LayerID.geography
    public static let supportedModes: Set<ProjectionMode> = [.map]
}

public enum FlightsLayerKind: ProjectionMarkLayerKind {
    public typealias Payload = ProjectionMarkLayerPayload
    public static let id = LayerID.flights
    public static let supportedModes: Set<ProjectionMode> = [.map, .trueSky]
}

public enum StarsLayerKind: ProjectionMarkLayerKind {
    public typealias Payload = ProjectionMarkLayerPayload
    public static let id = LayerID.stars
    public static let supportedModes: Set<ProjectionMode> = [.trueSky]
}

public enum SatellitesLayerKind: ProjectionMarkLayerKind {
    public typealias Payload = ProjectionMarkLayerPayload
    public static let id = LayerID.satellites
    public static let supportedModes: Set<ProjectionMode> = [.map, .trueSky]
}

public enum TransitNetworkLayerKind: ProjectionLineLayerKind {
    public typealias Payload = ProjectionLineLayerPayload
    public static let id = LayerID.transitNetwork
    public static let supportedModes: Set<ProjectionMode> = [.map]
}

public enum TransitVehiclesLayerKind: ProjectionMarkLayerKind {
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

    private init(observedAt: Date, payload: Layer.Payload) {
        self.observedAt = observedAt
        self.payload = payload
    }

    /// Creates the empty frame for a compile-time layer kind.
    public static func empty(observedAt: Date) -> Self {
        Self(observedAt: observedAt, payload: .empty)
    }

    public var layerID: LayerID {
        Layer.id
    }

    public var description: String {
        let counts = switch payload.erasedContent {
            case let .marks(marks): "marks=\(marks.count) lines=0"
            case let .lines(lines): "marks=0 lines=\(lines.count)"
        }
        return "<LayerFrame layer=\(Layer.id.rawValue) \(counts)>"
    }

    public var debugDescription: String {
        description
    }
}

extension ProjectionLayerFrame where Layer: ProjectionMarkLayerKind {
    public init(observedAt: Date, marks: [ProjectionMark]) {
        let payload = ProjectionMarkLayerPayload(marks: marks)
        precondition(payload.marks.allSatisfy { $0.id.layerID == Layer.id })
        self.init(observedAt: observedAt, payload: payload)
    }

    public var marks: [ProjectionMark] {
        payload.marks
    }
}

extension ProjectionLayerFrame where Layer: ProjectionLineLayerKind {
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

struct ProjectedLineProvenance: Hashable {
    let layerID: LayerID
    let sourceRevision: Date
    let mapCenter: GeoCoordinate
    let viewport: ProjectionViewport
    let calibration: ProjectionCalibration
    let geometry: ProjectionGeometry
}

/// Identifies one cached static-line projection for UI path reuse.
public struct ProjectionLineRevisionID: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    private enum Storage: Hashable {
        case projection(ProjectedLineProvenance)
        #if DEBUG
            case testing(UInt64)
        #endif
    }

    private let storage: Storage

    init(provenance: ProjectedLineProvenance) {
        storage = .projection(provenance)
    }

    #if DEBUG
        @_spi(Testing) public static func testing(rawValue: UInt64) -> Self {
            Self(storage: .testing(rawValue))
        }

        private init(storage: Storage) {
            self.storage = storage
        }
    #endif

    public var description: String {
        "<ProjectionLineRevisionID redacted>"
    }

    public var debugDescription: String {
        description
    }
}

public typealias GeographyProjectionID = ProjectionLineRevisionID

/// Cached normalized line segments and their stable render identity.
public struct ProjectedLineCollection: Hashable, Sendable {
    public let id: ProjectionLineRevisionID
    public let segments: [ProjectedLineSegment]

    init(provenance: ProjectedLineProvenance, segments: [ProjectedLineSegment]) {
        id = ProjectionLineRevisionID(provenance: provenance)
        self.segments = segments
    }

    #if DEBUG
        @_spi(Testing) public static func testing(
            id: ProjectionLineRevisionID,
            segments: [ProjectedLineSegment],
        ) -> Self {
            Self(id: id, segments: segments)
        }

        private init(id: ProjectionLineRevisionID, segments: [ProjectedLineSegment]) {
            self.id = id
            self.segments = segments
        }
    #endif
}

public typealias ProjectedGeography = ProjectedLineCollection

/// One projected payload whose shape is fixed by its layer kind.
public protocol ProjectedLayerPayload: Hashable, Sendable {}

public struct ProjectedMarkLayerPayload: ProjectedLayerPayload {
    public let marks: [ProjectedMark]

    public init(marks: [ProjectedMark]) {
        self.marks = retainingLastMarkByIdentity(marks, identity: \.id)
    }
}

public struct ProjectedLineLayerPayload: ProjectedLayerPayload {
    public let lines: ProjectedLineCollection
    let provenance: ProjectedLineProvenance?

    init(
        lines: ProjectedLineCollection,
        provenance: ProjectedLineProvenance,
    ) {
        self.lines = lines
        self.provenance = provenance
    }

    #if DEBUG
        init(testingLines lines: ProjectedLineCollection) {
            self.lines = lines
            provenance = nil
        }
    #endif
}

/// A projected frame whose identity and payload shape are fixed by its layer kind.
public struct ProjectedLayerFrame<Layer: ProjectionLayerKind>: Hashable, Sendable {
    public let payload: Layer.Payload.Projected

    private init(payload: Layer.Payload.Projected) {
        self.payload = payload
    }

    public var layerID: LayerID {
        Layer.id
    }
}

extension ProjectedLayerFrame where Layer: ProjectionMarkLayerKind {
    /// Creates a projected mark layer after its erased mark IDs pass the layer boundary check.
    public init(marks: [ProjectedMark]) {
        let payload = ProjectedMarkLayerPayload(marks: marks)
        precondition(payload.marks.allSatisfy { $0.id.layerID == Layer.id })
        self.init(payload: payload)
    }

    public var marks: [ProjectedMark] {
        payload.marks
    }
}

extension ProjectedLayerFrame where Layer: ProjectionLineLayerKind {
    init(
        segments: [ProjectedLineSegment],
        provenance: ProjectedLineProvenance,
    ) {
        self.init(payload: ProjectedLineLayerPayload(
            lines: ProjectedLineCollection(provenance: provenance, segments: segments),
            provenance: provenance,
        ))
    }

    public var lines: ProjectedLineCollection {
        payload.lines
    }

    #if DEBUG
        @_spi(Testing) public static func testing(lines: ProjectedLineCollection) -> Self {
            Self(payload: ProjectedLineLayerPayload(testingLines: lines))
        }
    #endif
}

/// The projected layers for Air & Space in Map mode.
public struct AirAndSpaceMapProjectedFrame: Hashable, Sendable {
    public let generatedAt: Date
    public let geography: ProjectedLayerFrame<GeographyLayerKind>?
    public let flights: ProjectedLayerFrame<FlightsLayerKind>?
    public let satellites: ProjectedLayerFrame<SatellitesLayerKind>?

    public init(
        generatedAt: Date,
        geography: ProjectedLayerFrame<GeographyLayerKind>?,
        flights: ProjectedLayerFrame<FlightsLayerKind>?,
        satellites: ProjectedLayerFrame<SatellitesLayerKind>?,
    ) {
        self.generatedAt = generatedAt
        self.geography = geography
        self.flights = flights
        self.satellites = satellites
    }
}

/// The projected layers for Air & Space in True Sky mode.
public struct AirAndSpaceTrueSkyProjectedFrame: Hashable, Sendable {
    public let generatedAt: Date
    public let flights: ProjectedLayerFrame<FlightsLayerKind>?
    public let stars: ProjectedLayerFrame<StarsLayerKind>?
    public let satellites: ProjectedLayerFrame<SatellitesLayerKind>?

    public init(
        generatedAt: Date,
        flights: ProjectedLayerFrame<FlightsLayerKind>?,
        stars: ProjectedLayerFrame<StarsLayerKind>?,
        satellites: ProjectedLayerFrame<SatellitesLayerKind>?,
    ) {
        self.generatedAt = generatedAt
        self.flights = flights
        self.stars = stars
        self.satellites = satellites
    }
}

/// One Air & Space projection. True Sky cannot carry Geography.
public enum AirAndSpaceProjectedFrame: Hashable, Sendable {
    case map(AirAndSpaceMapProjectedFrame)
    case trueSky(AirAndSpaceTrueSkyProjectedFrame)

    public var mode: ProjectionMode {
        switch self {
            case .map: .map
            case .trueSky: .trueSky
        }
    }

    public var generatedAt: Date {
        switch self {
            case let .map(frame): frame.generatedAt
            case let .trueSky(frame): frame.generatedAt
        }
    }

    public var marks: [ProjectedMark] {
        switch self {
            case let .map(frame):
                [frame.flights?.marks, frame.satellites?.marks]
                    .compactMap(\.self)
                    .flatMap(\.self)
            case let .trueSky(frame):
                [frame.flights?.marks, frame.stars?.marks, frame.satellites?.marks]
                    .compactMap(\.self)
                    .flatMap(\.self)
        }
    }
}

/// The projected layers for Transit. Transit supports Map mode only.
public struct TransitProjectedFrame: Hashable, Sendable {
    public let generatedAt: Date
    public let geography: ProjectedLayerFrame<GeographyLayerKind>?
    public let network: ProjectedLayerFrame<TransitNetworkLayerKind>?
    public let vehicles: ProjectedLayerFrame<TransitVehiclesLayerKind>?

    public init(
        generatedAt: Date,
        geography: ProjectedLayerFrame<GeographyLayerKind>?,
        network: ProjectedLayerFrame<TransitNetworkLayerKind>?,
        vehicles: ProjectedLayerFrame<TransitVehiclesLayerKind>?,
    ) {
        self.generatedAt = generatedAt
        self.geography = geography
        self.network = network
        self.vehicles = vehicles
    }

    public var marks: [ProjectedMark] {
        vehicles?.marks ?? []
    }
}

/// One projected experience with a compile-time layer set and projection mode.
public enum ProjectedExperienceFrame: Hashable, Sendable {
    case airAndSpace(AirAndSpaceProjectedFrame)
    case transit(TransitProjectedFrame)

    public var experienceID: ProjectionExperienceID {
        switch self {
            case .airAndSpace: .airAndSpace
            case .transit: .transit
        }
    }

    public var mode: ProjectionMode {
        switch self {
            case let .airAndSpace(frame): frame.mode
            case .transit: .map
        }
    }

    public var generatedAt: Date {
        switch self {
            case let .airAndSpace(frame): frame.generatedAt
            case let .transit(frame): frame.generatedAt
        }
    }

    public var marks: [ProjectedMark] {
        switch self {
            case let .airAndSpace(frame): frame.marks
            case let .transit(frame): frame.marks
        }
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
            #if DEBUG
                case .testing:
                    preconditionFailure("A test-only experience must supply its own semantic frame")
            #endif
        }
    }

    public var experienceID: ProjectionExperienceID {
        switch self {
            case .airAndSpace: .airAndSpace
            case .transit: .transit
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

/// One typed Air & Space request for the projection engine.
public struct AirAndSpaceProjectionInput: Hashable, Sendable {
    public let frame: AirAndSpaceExperienceFrame
    public let viewport: AirAndSpaceProjectionViewport

    public init(
        frame: AirAndSpaceExperienceFrame,
        viewport: AirAndSpaceProjectionViewport,
    ) {
        self.frame = frame
        self.viewport = viewport
    }
}

/// One typed Transit request for the projection engine.
public struct TransitProjectionInput: Hashable, Sendable {
    public let frame: TransitExperienceFrame
    public let viewport: MapViewport
    public let geography: GeographyLayerVisibility

    public init(
        frame: TransitExperienceFrame,
        viewport: MapViewport,
        geography: GeographyLayerVisibility,
    ) {
        self.frame = frame
        self.viewport = viewport
        self.geography = geography
    }
}

/// A projection request with a compile-time experience, layer set, and mode set.
public enum ProjectionExperienceInput: Hashable, Sendable {
    case airAndSpace(AirAndSpaceProjectionInput)
    case transit(TransitProjectionInput)

    public var experienceFrame: ProjectionExperienceFrame {
        switch self {
            case let .airAndSpace(input): .airAndSpace(input.frame)
            case let .transit(input): .transit(input.frame)
        }
    }

    public var viewport: ProjectionViewport {
        switch self {
            case let .airAndSpace(input): input.viewport.viewport
            case let .transit(input): .map(input.viewport)
        }
    }

    public var requestsGeography: Bool {
        switch self {
            case let .airAndSpace(input): input.viewport.requestsGeography
            case let .transit(input): input.geography == .visible
        }
    }
}

/// Air & Space input after static lines are projected for the current geometry.
public struct PreparedAirAndSpaceProjectionInput: Hashable, Sendable {
    let viewport: AirAndSpaceProjectionViewport
    let geography: ProjectedLayerFrame<GeographyLayerKind>?
    let flights: ProjectionLayerFrame<FlightsLayerKind>?
    let stars: ProjectionLayerFrame<StarsLayerKind>?
    let satellites: ProjectionLayerFrame<SatellitesLayerKind>?

    public init(
        input: AirAndSpaceProjectionInput,
        geography: ProjectedLayerFrame<GeographyLayerKind>?,
    ) {
        viewport = input.viewport
        self.geography = input.viewport.requestsGeography ? geography : nil
        flights = input.frame.flights
        stars = input.frame.stars
        satellites = input.frame.satellites
    }
}

/// One projected line layer paired with the semantic revision that produced it.
struct PreparedProjectionLineLayer<Layer: ProjectionLineLayerKind>: Hashable {
    let sourceRevision: Date
    let frame: ProjectedLayerFrame<Layer>

    fileprivate init(
        source: ProjectionLayerFrame<Layer>,
        frame: ProjectedLayerFrame<Layer>,
    ) {
        sourceRevision = source.observedAt
        self.frame = frame
    }
}

/// Transit input after static lines are projected for the current geometry.
public struct PreparedTransitProjectionInput: Hashable, Sendable {
    let viewport: MapViewport
    let geography: ProjectedLayerFrame<GeographyLayerKind>?
    let network: PreparedProjectionLineLayer<TransitNetworkLayerKind>?
    let vehicles: ProjectionLayerFrame<TransitVehiclesLayerKind>?

    public init(
        input: TransitProjectionInput,
        geography: ProjectedLayerFrame<GeographyLayerKind>?,
        projectNetwork: (
            ProjectionLayerFrame<TransitNetworkLayerKind>
        ) throws -> ProjectedLayerFrame<TransitNetworkLayerKind>,
    ) rethrows {
        viewport = input.viewport
        self.geography = input.geography == .visible ? geography : nil
        network = try input.frame.network.map { source in
            try PreparedProjectionLineLayer(
                source: source,
                frame: projectNetwork(source),
            )
        }
        vehicles = input.frame.vehicles
    }
}

/// One closed projection-engine input with its legal semantic and static layers.
public enum PreparedProjectionExperienceInput: Hashable, Sendable {
    case airAndSpace(PreparedAirAndSpaceProjectionInput)
    case transit(PreparedTransitProjectionInput)
}

/// A prepared static line does not match its semantic source or projection context.
public enum ProjectionPreparationError: Error, Hashable, Sendable {
    case missingLineProvenance(layerID: LayerID)
    case layerIdentityMismatch(layerID: LayerID)
    case sourceRevisionMismatch(layerID: LayerID)
    case projectionContextMismatch(layerID: LayerID)
}
