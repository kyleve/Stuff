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
    case transitStop = "transit-stop"
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

public struct TransitStopMarkID: Hashable, Sendable {
    public let stopID: TransitStopID
    public let context: String

    public init(stopID: TransitStopID, context: String) {
        precondition(context.isEmpty == false)
        self.stopID = stopID
        self.context = context
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
    case transitStop(TransitStopMarkID)

    public var layerID: LayerID {
        switch self {
            case .aircraft, .airport: .flights
            case .star: .stars
            case .satellite: .satellites
            case .transitVehicle, .transitStop: .transitVehicles
        }
    }

    public var namespace: LayerMarkNamespace {
        switch self {
            case .aircraft: .aircraft
            case .airport: .airport
            case .star: .star
            case .satellite: .satellite
            case .transitVehicle: .transitVehicle
            case .transitStop: .transitStop
        }
    }

    public var rawValue: String {
        switch self {
            case let .aircraft(id): "\(id.kind.rawValue)/\(id.rawValue)"
            case let .airport(id): String(id.rawValue)
            case let .star(id): id.rawValue
            case let .satellite(id): id.rawValue
            case let .transitVehicle(id): id.rawValue
            case let .transitStop(id): "\(id.stopID.rawValue)/\(id.context)"
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
    case transitVehicle(TransitVehicleGlyphDescriptor)
    case transitStop(TransitStopGlyphDescriptor)
}

public struct TransitVehicleGlyphDescriptor: Hashable, Sendable {
    public let routeLabel: String
    public let color: TransitColor
    public let confidence: TransitPositionConfidence

    public init(
        routeLabel: String,
        color: TransitColor,
        confidence: TransitPositionConfidence,
    ) {
        precondition(routeLabel.isEmpty == false)
        self.routeLabel = routeLabel
        self.color = color
        self.confidence = confidence
    }
}

public struct TransitStopGlyphDescriptor: Hashable, Sendable {
    public let color: TransitColor

    public init(color: TransitColor) {
        self.color = color
    }
}

public struct TransitMotionPoint: Hashable, Sendable {
    public let coordinate: GeoCoordinate
    public let distance: Double

    public init(coordinate: GeoCoordinate, distance: Double) {
        precondition(distance.isFinite && distance >= 0)
        self.coordinate = coordinate
        self.distance = distance
    }
}

public struct TransitProjectionMotion: Hashable, Sendable {
    public let points: [TransitMotionPoint]
    public let startsAt: Date
    public let endsAt: Date

    public init(points: [TransitMotionPoint], startsAt: Date, endsAt: Date) {
        precondition(points.count >= 2)
        precondition(points.map(\.distance) == points.map(\.distance).sorted())
        precondition(endsAt > startsAt)
        self.points = points
        self.startsAt = startsAt
        self.endsAt = endsAt
    }
}

/// One mark identity and glyph family carried through semantic and projected frames.
public protocol ProjectionMarkElement: Hashable, Sendable {
    associatedtype ID: Hashable & Sendable

    var id: ID { get }
    var glyph: ProjectionGlyph { get }
}

/// The closed element family for Flights. Airport identity comes from its glyph descriptor.
public enum FlightsMarkElement: Hashable, Sendable, ProjectionMarkElement {
    public enum ID: Hashable, Sendable {
        case aircraft(AircraftID)
        case airport(AirportID)
    }

    case aircraft(id: AircraftID, glyph: AircraftGlyphDescriptor)
    case airport(AirportGlyphDescriptor)

    public var id: ID {
        switch self {
            case let .aircraft(id, _): .aircraft(id)
            case let .airport(descriptor): .airport(descriptor.airportID)
        }
    }

    public var glyph: ProjectionGlyph {
        switch self {
            case let .aircraft(_, descriptor): .aircraft(descriptor)
            case let .airport(descriptor): .airport(descriptor)
        }
    }
}

/// The closed element family for Stars.
public struct StarMarkElement: Hashable, Sendable, ProjectionMarkElement {
    public let id: StarID

    public init(id: StarID) {
        self.id = id
    }

    public var glyph: ProjectionGlyph {
        .star
    }
}

/// The closed element family for Satellites.
public struct SatelliteMarkElement: Hashable, Sendable, ProjectionMarkElement {
    public let id: SatelliteID

    public init(id: SatelliteID) {
        self.id = id
    }

    public var glyph: ProjectionGlyph {
        .satellite
    }
}

/// The closed element family for Transit vehicles and their referenced stops.
public enum TransitVehicleMarkElement: Hashable, Sendable, ProjectionMarkElement {
    public enum ID: Hashable, Sendable {
        case vehicle(TransitVehicleID)
        case stop(TransitStopMarkID)
    }

    case vehicle(id: TransitVehicleID, descriptor: TransitVehicleGlyphDescriptor)
    case stop(id: TransitStopMarkID, descriptor: TransitStopGlyphDescriptor)

    public var id: ID {
        switch self {
            case let .vehicle(id, _): .vehicle(id)
            case let .stop(id, _): .stop(id)
        }
    }

    public var glyph: ProjectionGlyph {
        switch self {
            case let .vehicle(_, descriptor): .transitVehicle(descriptor)
            case let .stop(_, descriptor): .transitStop(descriptor)
        }
    }
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
    case transitRetrying(since: Date)
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

public struct ProjectionMark<Element: ProjectionMarkElement>: Hashable, Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let element: Element
    public let anchor: ProjectionAnchor
    public let label: ProjectionLabel?
    public let prominence: ProjectionProminence
    public let velocity: ProjectionVelocity?
    public let transitMotion: TransitProjectionMotion?
    public let freshness: MarkFreshness

    public init(
        element: Element,
        anchor: ProjectionAnchor,
        label: ProjectionLabel?,
        prominence: ProjectionProminence,
        velocity: ProjectionVelocity?,
        transitMotion: TransitProjectionMotion?,
        freshness: MarkFreshness,
    ) {
        self.element = element
        self.anchor = anchor
        self.label = label
        self.prominence = prominence
        self.velocity = velocity
        self.transitMotion = transitMotion
        self.freshness = freshness
    }

    public init(
        element: Element,
        anchor: ProjectionAnchor,
        label: ProjectionLabel?,
        prominence: ProjectionProminence,
        velocity: ProjectionVelocity?,
        freshness: MarkFreshness,
    ) {
        self.init(
            element: element,
            anchor: anchor,
            label: label,
            prominence: prominence,
            velocity: velocity,
            transitMotion: nil,
            freshness: freshness,
        )
    }

    public var id: Element.ID {
        element.id
    }

    public var glyph: ProjectionGlyph {
        element.glyph
    }

    public var description: String {
        "<ProjectionMark redacted>"
    }

    public var debugDescription: String {
        description
    }
}

private func retainingLastMarkByIdentity<Mark, ID: Hashable>(
    _ marks: [Mark],
    identity: (Mark) -> ID,
) -> [Mark] {
    var result: [Mark] = []
    result.reserveCapacity(marks.count)
    var indexByID: [ID: Int] = [:]
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
    var elementCount: Int { get }
}

public struct ProjectionMarkLayerPayload<Element: ProjectionMarkElement>:
    ProjectionLayerPayload
{
    public typealias Projected = ProjectedMarkLayerPayload<Element>
    public static var empty: Self {
        Self(marks: [])
    }

    public let marks: [ProjectionMark<Element>]

    public init(marks: [ProjectionMark<Element>]) {
        self.marks = retainingLastMarkByIdentity(marks, identity: \.id)
    }

    public var elementCount: Int {
        marks.count
    }
}

public struct ProjectionLineLayerPayload<Style: ProjectionLineStyle>: ProjectionLayerPayload {
    public typealias Projected = ProjectedLineLayerPayload<Style>
    public static var empty: Self {
        Self(lines: [])
    }

    public let lines: [ProjectionPolyline<Style>]

    public init(lines: [ProjectionPolyline<Style>]) {
        self.lines = lines
    }

    public var elementCount: Int {
        lines.count
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
    where Payload == ProjectionMarkLayerPayload<MarkElement>
{
    associatedtype MarkElement: ProjectionMarkElement
}

/// A layer whose semantic and projected forms both contain lines.
public protocol ProjectionLineLayerKind: ProjectionLayerKind
    where Payload == ProjectionLineLayerPayload<LineStyle>
{
    associatedtype LineStyle: ProjectionLineStyle
}

public enum GeographyLayerKind: ProjectionLineLayerKind {
    public typealias LineStyle = GeographyLineKind
    public typealias Payload = ProjectionLineLayerPayload<LineStyle>
    public static let id = LayerID.geography
    public static let supportedModes: Set<ProjectionMode> = [.map]
}

public enum FlightsLayerKind: ProjectionMarkLayerKind {
    public typealias MarkElement = FlightsMarkElement
    public typealias Payload = ProjectionMarkLayerPayload<MarkElement>
    public static let id = LayerID.flights
    public static let supportedModes: Set<ProjectionMode> = [.map, .trueSky]
}

public enum StarsLayerKind: ProjectionMarkLayerKind {
    public typealias MarkElement = StarMarkElement
    public typealias Payload = ProjectionMarkLayerPayload<MarkElement>
    public static let id = LayerID.stars
    public static let supportedModes: Set<ProjectionMode> = [.trueSky]
}

public enum SatellitesLayerKind: ProjectionMarkLayerKind {
    public typealias MarkElement = SatelliteMarkElement
    public typealias Payload = ProjectionMarkLayerPayload<MarkElement>
    public static let id = LayerID.satellites
    public static let supportedModes: Set<ProjectionMode> = [.map, .trueSky]
}

public enum TransitNetworkLayerKind: ProjectionLineLayerKind {
    public typealias LineStyle = TransitNetworkLineStyle
    public typealias Payload = ProjectionLineLayerPayload<LineStyle>
    public static let id = LayerID.transitNetwork
    public static let supportedModes: Set<ProjectionMode> = [.map]
}

public enum TransitVehiclesLayerKind: ProjectionMarkLayerKind {
    public typealias MarkElement = TransitVehicleMarkElement
    public typealias Payload = ProjectionMarkLayerPayload<MarkElement>
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
        "<LayerFrame layer=\(Layer.id.rawValue) elements=\(payload.elementCount)>"
    }

    public var debugDescription: String {
        description
    }
}

extension ProjectionLayerFrame where Layer: ProjectionMarkLayerKind {
    public init(observedAt: Date, marks: [ProjectionMark<Layer.MarkElement>]) {
        self.init(observedAt: observedAt, payload: ProjectionMarkLayerPayload(marks: marks))
    }

    public var marks: [ProjectionMark<Layer.MarkElement>] {
        payload.marks
    }
}

extension ProjectionLayerFrame where Layer: ProjectionLineLayerKind {
    public init(observedAt: Date, lines: [ProjectionPolyline<Layer.LineStyle>]) {
        self.init(observedAt: observedAt, payload: ProjectionLineLayerPayload(lines: lines))
    }

    public var lines: [ProjectionPolyline<Layer.LineStyle>] {
        payload.lines
    }
}

extension ProjectionLayerFrame where Layer == GeographyLayerKind {
    public var geographicLines: [GeographicPolyline] {
        lines
    }
}

#if DEBUG
    /// A raw mark element available only to adversarial tests at the Testing SPI.
    public struct TestingProjectionMarkElement: Hashable, Sendable,
        ProjectionMarkElement
    {
        public let id: LayerMarkID
        public let glyph: ProjectionGlyph

        @_spi(Testing) public init(id: LayerMarkID, glyph: ProjectionGlyph) {
            self.id = id
            self.glyph = glyph
        }
    }

    @_spi(Testing) public typealias TestingProjectionMark =
        ProjectionMark<TestingProjectionMarkElement>

    extension ProjectionMark where Element == TestingProjectionMarkElement {
        @_spi(Testing) public init(
            id: LayerMarkID,
            anchor: ProjectionAnchor,
            glyph: ProjectionGlyph,
            label: ProjectionLabel?,
            prominence: ProjectionProminence,
            velocity: ProjectionVelocity?,
            freshness: MarkFreshness,
        ) {
            self.init(
                element: TestingProjectionMarkElement(id: id, glyph: glyph),
                anchor: anchor,
                label: label,
                prominence: prominence,
                velocity: velocity,
                freshness: freshness,
            )
        }
    }

    /// A raw line style available only to adversarial tests at the Testing SPI.
    public struct ProjectionLineStyleID: Hashable, Sendable,
        ProjectionLineStyle
    {
        private enum Storage: Hashable {
            case geography(GeographyLineKind)
            case transitRoute(TransitNetworkLineStyle)
        }

        private let storage: Storage

        @_spi(Testing) public static func transitRoute(
            _ style: TransitNetworkLineStyle,
        ) -> Self {
            Self(storage: .transitRoute(style))
        }

        private init(storage: Storage) {
            self.storage = storage
        }

        @_spi(Testing) public init(geographyKind: GeographyLineKind) {
            storage = .geography(geographyKind)
        }

        public var geographyKind: GeographyLineKind? {
            switch storage {
                case let .geography(kind): kind
                case .transitRoute: nil
            }
        }

        @_spi(Testing) public var transitRouteStyle: TransitNetworkLineStyle? {
            guard case let .transitRoute(style) = storage else { return nil }
            return style
        }

        public var isTransitRoute: Bool {
            switch storage {
                case .geography: false
                case .transitRoute: true
            }
        }
    }

    @_spi(Testing) public typealias TestingProjectionPolyline =
        ProjectionPolyline<ProjectionLineStyleID>

    extension ProjectionPolyline where Style == ProjectionLineStyleID {
        @_spi(Testing) public init(
            styleID: ProjectionLineStyleID,
            detailLevel: GeographyDetailLevel,
            bounds: GeographicBounds,
            coordinates: [GeoCoordinate],
        ) throws {
            try self.init(
                style: styleID,
                detailLevel: detailLevel,
                bounds: bounds,
                coordinates: coordinates,
            )
        }

        public var styleID: ProjectionLineStyleID {
            style
        }
    }

    /// Raw heterogeneous input retained only for focused projection adversarial tests.
    @_spi(Testing) public enum LayerFrameContent: Hashable, Sendable {
        case marks([TestingProjectionMark])
        case lines([TestingProjectionPolyline])
    }

    @_spi(Testing) public struct LayerFrame: Hashable, Sendable {
        public let layerID: LayerID
        public let observedAt: Date
        public let content: LayerFrameContent

        @_spi(Testing) public init(
            layerID: LayerID,
            observedAt: Date,
            content: LayerFrameContent,
        ) {
            let canonicalContent: LayerFrameContent = switch content {
                case let .marks(marks):
                    .marks(retainingLastMarkByIdentity(marks, identity: \.id))
                case let .lines(lines): .lines(lines)
            }
            if case let .marks(marks) = canonicalContent {
                precondition(marks.allSatisfy { $0.id.layerID == layerID })
            }
            self.layerID = layerID
            self.observedAt = observedAt
            self.content = canonicalContent
        }

        public var marks: [TestingProjectionMark] {
            if case let .marks(marks) = content { marks } else { [] }
        }

        public var lines: [TestingProjectionPolyline] {
            if case let .lines(lines) = content { lines } else { [] }
        }
    }
#endif

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

public struct ProjectedMark<Element: ProjectionMarkElement>: Hashable, Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let element: Element
    public let point: ProjectionPoint
    /// Ground range in Map and slant range in True Sky. Non-geodetic layers may omit it.
    public let range: NauticalMiles?
    public let label: ProjectionLabel?
    /// Zero for primary marks and one for fully secondary marks. Intermediate
    /// values exist only while presentation interpolates between the states.
    public let secondaryProminence: Double
    public let orientationDegrees: Double?
    public let opacity: Double
    public let labelOpacity: Double
    public let altitudeIsApproximate: Bool

    public init(
        element: Element,
        point: ProjectionPoint,
        range: NauticalMiles?,
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
        self.element = element
        self.point = point
        self.range = range
        self.label = label
        self.secondaryProminence = secondaryProminence
        self.orientationDegrees = orientationDegrees
        self.opacity = opacity
        self.labelOpacity = labelOpacity
        self.altitudeIsApproximate = altitudeIsApproximate
    }

    public var id: Element.ID {
        element.id
    }

    public var glyph: ProjectionGlyph {
        element.glyph
    }

    public var description: String {
        "<ProjectedMark redacted>"
    }

    public var debugDescription: String {
        description
    }
}

#if DEBUG
    @_spi(Testing) public typealias TestingProjectedMark =
        ProjectedMark<TestingProjectionMarkElement>

    extension ProjectedMark where Element == TestingProjectionMarkElement {
        @_spi(Testing) public init(
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
            self.init(
                element: TestingProjectionMarkElement(id: id, glyph: glyph),
                point: point,
                range: range,
                label: label,
                secondaryProminence: secondaryProminence,
                orientationDegrees: orientationDegrees,
                opacity: opacity,
                labelOpacity: labelOpacity,
                altitudeIsApproximate: altitudeIsApproximate,
            )
        }
    }
#endif

public struct ProjectedLineSegment<Style: ProjectionLineStyle>: Hashable, Sendable {
    public let style: Style
    public let start: ProjectionPoint
    public let end: ProjectionPoint
    /// Whether the renderer must move to `start` instead of continuing the
    /// current path. This preserves joins and dash phase within a polyline.
    public let startsNewSubpath: Bool

    public init(
        style: Style,
        start: ProjectionPoint,
        end: ProjectionPoint,
        startsNewSubpath: Bool,
    ) {
        self.style = style
        self.start = start
        self.end = end
        self.startsNewSubpath = startsNewSubpath
    }
}

extension ProjectedLineSegment where Style == GeographyLineKind {
    public init(
        kind: GeographyLineKind,
        start: ProjectionPoint,
        end: ProjectionPoint,
        startsNewSubpath: Bool,
    ) {
        self.init(
            style: kind,
            start: start,
            end: end,
            startsNewSubpath: startsNewSubpath,
        )
    }

    public var kind: GeographyLineKind {
        style
    }
}

#if DEBUG
    @_spi(Testing) public typealias TestingProjectedLineSegment =
        ProjectedLineSegment<ProjectionLineStyleID>

    extension ProjectedLineSegment where Style == ProjectionLineStyleID {
        @_spi(Testing) public init(
            styleID: ProjectionLineStyleID,
            start: ProjectionPoint,
            end: ProjectionPoint,
            startsNewSubpath: Bool,
        ) {
            self.init(
                style: styleID,
                start: start,
                end: end,
                startsNewSubpath: startsNewSubpath,
            )
        }

        public var styleID: ProjectionLineStyleID {
            style
        }
    }
#endif

public typealias ProjectedGeographySegment = ProjectedLineSegment<GeographyLineKind>

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
public struct ProjectedLineCollection<Style: ProjectionLineStyle>: Hashable, Sendable {
    public let id: ProjectionLineRevisionID
    public let segments: [ProjectedLineSegment<Style>]

    init(provenance: ProjectedLineProvenance, segments: [ProjectedLineSegment<Style>]) {
        id = ProjectionLineRevisionID(provenance: provenance)
        self.segments = segments
    }

    #if DEBUG
        @_spi(Testing) public static func testing(
            id: ProjectionLineRevisionID,
            segments: [ProjectedLineSegment<Style>],
        ) -> Self {
            Self(id: id, segments: segments)
        }

        private init(id: ProjectionLineRevisionID, segments: [ProjectedLineSegment<Style>]) {
            self.id = id
            self.segments = segments
        }
    #endif
}

public typealias ProjectedGeography = ProjectedLineCollection<GeographyLineKind>

/// One projected payload whose shape is fixed by its layer kind.
public protocol ProjectedLayerPayload: Hashable, Sendable {}

public struct ProjectedMarkLayerPayload<Element: ProjectionMarkElement>:
    ProjectedLayerPayload
{
    public let marks: [ProjectedMark<Element>]

    public init(marks: [ProjectedMark<Element>]) {
        self.marks = retainingLastMarkByIdentity(marks, identity: \.id)
    }
}

public struct ProjectedLineLayerPayload<Style: ProjectionLineStyle>: ProjectedLayerPayload {
    public let lines: ProjectedLineCollection<Style>
    let provenance: ProjectedLineProvenance?

    init(
        lines: ProjectedLineCollection<Style>,
        provenance: ProjectedLineProvenance,
    ) {
        self.lines = lines
        self.provenance = provenance
    }

    #if DEBUG
        init(testingLines lines: ProjectedLineCollection<Style>) {
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
    public init(marks: [ProjectedMark<Layer.MarkElement>]) {
        self.init(payload: ProjectedMarkLayerPayload(marks: marks))
    }

    public var marks: [ProjectedMark<Layer.MarkElement>] {
        payload.marks
    }
}

extension ProjectedLayerFrame where Layer: ProjectionLineLayerKind {
    init(
        segments: [ProjectedLineSegment<Layer.LineStyle>],
        provenance: ProjectedLineProvenance,
    ) {
        self.init(payload: ProjectedLineLayerPayload(
            lines: ProjectedLineCollection(provenance: provenance, segments: segments),
            provenance: provenance,
        ))
    }

    public var lines: ProjectedLineCollection<Layer.LineStyle> {
        payload.lines
    }

    #if DEBUG
        @_spi(Testing) public static func testing(
            lines: ProjectedLineCollection<Layer.LineStyle>,
        ) -> Self {
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
    public let viewport: TransitMapViewport
    public let geography: GeographyLayerVisibility

    public init(
        frame: TransitExperienceFrame,
        viewport: TransitMapViewport,
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
    let viewport: TransitMapViewport
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
