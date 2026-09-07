import Foundation
#if DEBUG
    @_spi(Testing) import ThrowCore
#else
    import ThrowCore
#endif

/// One closed mark erased from a compiler-checked Core element family for presentation.
public struct PresentedMark: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    private enum Storage: Hashable {
        case flights(ThrowCore.ProjectedMark<FlightsMarkElement>)
        case stars(ThrowCore.ProjectedMark<StarMarkElement>)
        case satellites(ThrowCore.ProjectedMark<SatelliteMarkElement>)
        case transitVehicles(ThrowCore.ProjectedMark<TransitVehicleMarkElement>)
        #if DEBUG
            case testing(TestingProjectedMark)
        #endif
    }

    private let storage: Storage

    fileprivate init(_ mark: ThrowCore.ProjectedMark<FlightsMarkElement>) {
        storage = .flights(mark)
    }

    fileprivate init(_ mark: ThrowCore.ProjectedMark<StarMarkElement>) {
        storage = .stars(mark)
    }

    fileprivate init(_ mark: ThrowCore.ProjectedMark<SatelliteMarkElement>) {
        storage = .satellites(mark)
    }

    fileprivate init(_ mark: ThrowCore.ProjectedMark<TransitVehicleMarkElement>) {
        storage = .transitVehicles(mark)
    }

    #if DEBUG
        fileprivate init(_ mark: TestingProjectedMark) {
            storage = .testing(mark)
        }

        init(
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
            self.init(TestingProjectedMark(
                id: id,
                point: point,
                range: range,
                glyph: glyph,
                label: label,
                secondaryProminence: secondaryProminence,
                orientationDegrees: orientationDegrees,
                opacity: opacity,
                labelOpacity: labelOpacity,
                altitudeIsApproximate: altitudeIsApproximate,
            ))
        }
    #endif

    public var id: LayerMarkID {
        switch storage {
            case let .flights(mark): presentationID(mark.id)
            case let .stars(mark): .star(mark.id)
            case let .satellites(mark): .satellite(mark.id)
            case let .transitVehicles(mark): .transitVehicle(mark.id)
            #if DEBUG
                case let .testing(mark): mark.id
            #endif
        }
    }

    public var point: ProjectionPoint {
        switch storage {
            case let .flights(mark): mark.point
            case let .stars(mark): mark.point
            case let .satellites(mark): mark.point
            case let .transitVehicles(mark): mark.point
            #if DEBUG
                case let .testing(mark): mark.point
            #endif
        }
    }

    public var range: NauticalMiles? {
        switch storage {
            case let .flights(mark): mark.range
            case let .stars(mark): mark.range
            case let .satellites(mark): mark.range
            case let .transitVehicles(mark): mark.range
            #if DEBUG
                case let .testing(mark): mark.range
            #endif
        }
    }

    public var glyph: ProjectionGlyph {
        switch storage {
            case let .flights(mark): mark.glyph
            case let .stars(mark): mark.glyph
            case let .satellites(mark): mark.glyph
            case let .transitVehicles(mark): mark.glyph
            #if DEBUG
                case let .testing(mark): mark.glyph
            #endif
        }
    }

    public var label: ProjectionLabel? {
        switch storage {
            case let .flights(mark): mark.label
            case let .stars(mark): mark.label
            case let .satellites(mark): mark.label
            case let .transitVehicles(mark): mark.label
            #if DEBUG
                case let .testing(mark): mark.label
            #endif
        }
    }

    public var secondaryProminence: Double {
        switch storage {
            case let .flights(mark): mark.secondaryProminence
            case let .stars(mark): mark.secondaryProminence
            case let .satellites(mark): mark.secondaryProminence
            case let .transitVehicles(mark): mark.secondaryProminence
            #if DEBUG
                case let .testing(mark): mark.secondaryProminence
            #endif
        }
    }

    public var orientationDegrees: Double? {
        switch storage {
            case let .flights(mark): mark.orientationDegrees
            case let .stars(mark): mark.orientationDegrees
            case let .satellites(mark): mark.orientationDegrees
            case let .transitVehicles(mark): mark.orientationDegrees
            #if DEBUG
                case let .testing(mark): mark.orientationDegrees
            #endif
        }
    }

    public var opacity: Double {
        switch storage {
            case let .flights(mark): mark.opacity
            case let .stars(mark): mark.opacity
            case let .satellites(mark): mark.opacity
            case let .transitVehicles(mark): mark.opacity
            #if DEBUG
                case let .testing(mark): mark.opacity
            #endif
        }
    }

    public var labelOpacity: Double {
        switch storage {
            case let .flights(mark): mark.labelOpacity
            case let .stars(mark): mark.labelOpacity
            case let .satellites(mark): mark.labelOpacity
            case let .transitVehicles(mark): mark.labelOpacity
            #if DEBUG
                case let .testing(mark): mark.labelOpacity
            #endif
        }
    }

    public var altitudeIsApproximate: Bool {
        switch storage {
            case let .flights(mark): mark.altitudeIsApproximate
            case let .stars(mark): mark.altitudeIsApproximate
            case let .satellites(mark): mark.altitudeIsApproximate
            case let .transitVehicles(mark): mark.altitudeIsApproximate
            #if DEBUG
                case let .testing(mark): mark.altitudeIsApproximate
            #endif
        }
    }

    public var description: String {
        "<PresentedMark redacted>"
    }

    public var debugDescription: String {
        description
    }

    fileprivate var layerID: LayerID {
        switch storage {
            case .flights: .flights
            case .stars: .stars
            case .satellites: .satellites
            case .transitVehicles: .transitVehicles
            #if DEBUG
                case let .testing(mark): mark.id.layerID
            #endif
        }
    }

    fileprivate var flightsMark: ThrowCore.ProjectedMark<FlightsMarkElement>? {
        if case let .flights(mark) = storage { mark } else { nil }
    }

    fileprivate var starMark: ThrowCore.ProjectedMark<StarMarkElement>? {
        if case let .stars(mark) = storage { mark } else { nil }
    }

    fileprivate var satelliteMark: ThrowCore.ProjectedMark<SatelliteMarkElement>? {
        if case let .satellites(mark) = storage { mark } else { nil }
    }

    fileprivate var transitVehicleMark: ThrowCore.ProjectedMark<TransitVehicleMarkElement>? {
        if case let .transitVehicles(mark) = storage { mark } else { nil }
    }

    #if DEBUG
        fileprivate var testingMark: TestingProjectedMark? {
            if case let .testing(mark) = storage { mark } else { nil }
        }
    #endif

    func replacing(
        point: ProjectionPoint,
        label: ProjectionLabel?,
        secondaryProminence: Double,
        orientationDegrees: Double?,
        opacity: Double,
        labelOpacity: Double,
    ) -> Self {
        switch storage {
            case let .flights(mark):
                Self(replacingFields(
                    mark,
                    point: point,
                    label: label,
                    secondaryProminence: secondaryProminence,
                    orientationDegrees: orientationDegrees,
                    opacity: opacity,
                    labelOpacity: labelOpacity,
                ))
            case let .stars(mark):
                Self(replacingFields(
                    mark,
                    point: point,
                    label: label,
                    secondaryProminence: secondaryProminence,
                    orientationDegrees: orientationDegrees,
                    opacity: opacity,
                    labelOpacity: labelOpacity,
                ))
            case let .satellites(mark):
                Self(replacingFields(
                    mark,
                    point: point,
                    label: label,
                    secondaryProminence: secondaryProminence,
                    orientationDegrees: orientationDegrees,
                    opacity: opacity,
                    labelOpacity: labelOpacity,
                ))
            case let .transitVehicles(mark):
                Self(replacingFields(
                    mark,
                    point: point,
                    label: label,
                    secondaryProminence: secondaryProminence,
                    orientationDegrees: orientationDegrees,
                    opacity: opacity,
                    labelOpacity: labelOpacity,
                ))
            #if DEBUG
                case let .testing(mark):
                    Self(replacingFields(
                        mark,
                        point: point,
                        label: label,
                        secondaryProminence: secondaryProminence,
                        orientationDegrees: orientationDegrees,
                        opacity: opacity,
                        labelOpacity: labelOpacity,
                    ))
            #endif
        }
    }

    func replacing(with fields: PresentedMarkFields) -> Self {
        replacing(
            point: fields.point,
            label: fields.label,
            secondaryProminence: fields.secondaryProminence,
            orientationDegrees: fields.orientationDegrees,
            opacity: fields.opacity,
            labelOpacity: fields.labelOpacity,
        )
    }
}

/// Presentation-only fields that can change without changing a mark's element family.
struct PresentedMarkFields: Hashable {
    let point: ProjectionPoint
    let label: ProjectionLabel?
    let secondaryProminence: Double
    let orientationDegrees: Double?
    let opacity: Double
    let labelOpacity: Double

    init(
        point: ProjectionPoint,
        label: ProjectionLabel?,
        secondaryProminence: Double,
        orientationDegrees: Double?,
        opacity: Double,
        labelOpacity: Double,
    ) {
        precondition((0 ... 1).contains(secondaryProminence))
        precondition((0 ... 1).contains(opacity))
        precondition((0 ... 1).contains(labelOpacity))
        self.point = point
        self.label = label
        self.secondaryProminence = secondaryProminence
        self.orientationDegrees = orientationDegrees
        self.opacity = opacity
        self.labelOpacity = labelOpacity
    }

    init(_ mark: PresentedMark) {
        self.init(
            point: mark.point,
            label: mark.label,
            secondaryProminence: mark.secondaryProminence,
            orientationDegrees: mark.orientationDegrees,
            opacity: mark.opacity,
            labelOpacity: mark.labelOpacity,
        )
    }
}

func presentationID(_ id: FlightsMarkElement.ID) -> LayerMarkID {
    switch id {
        case let .aircraft(id): .aircraft(id)
        case let .airport(id): .airport(id)
    }
}

private func replacingFields<Element: ProjectionMarkElement>(
    _ mark: ThrowCore.ProjectedMark<Element>,
    point: ProjectionPoint,
    label: ProjectionLabel?,
    secondaryProminence: Double,
    orientationDegrees: Double?,
    opacity: Double,
    labelOpacity: Double,
) -> ThrowCore.ProjectedMark<Element> {
    ThrowCore.ProjectedMark(
        element: mark.element,
        point: point,
        range: mark.range,
        label: label,
        secondaryProminence: secondaryProminence,
        orientationDegrees: orientationDegrees,
        opacity: opacity,
        labelOpacity: labelOpacity,
        altitudeIsApproximate: mark.altitudeIsApproximate,
    )
}

private func replacingFields<Element: ProjectionMarkElement>(
    _ mark: ThrowCore.ProjectedMark<Element>,
    with fields: PresentedMarkFields,
) -> ThrowCore.ProjectedMark<Element> {
    replacingFields(
        mark,
        point: fields.point,
        label: fields.label,
        secondaryProminence: fields.secondaryProminence,
        orientationDegrees: fields.orientationDegrees,
        opacity: fields.opacity,
        labelOpacity: fields.labelOpacity,
    )
}

/// The renderer payload after the typed Core projection crosses into presentation.
enum ProjectedLayerContent: Hashable {
    case geography(ProjectedGeography)
    case flights([ThrowCore.ProjectedMark<FlightsMarkElement>])
    case stars([ThrowCore.ProjectedMark<StarMarkElement>])
    case satellites([ThrowCore.ProjectedMark<SatelliteMarkElement>])
    case transitNetwork(ProjectedLineCollection<TransitNetworkLineStyle>)
    case transitVehicles([ThrowCore.ProjectedMark<TransitVehicleMarkElement>])
    #if DEBUG
        case testingMarks(layerID: LayerID, marks: [TestingProjectedMark])
    #endif
}

/// One renderer layer whose identity and element family come from one closed payload case.
struct ProjectedLayer: Identifiable, Hashable {
    let opacity: Double
    let content: ProjectedLayerContent

    fileprivate init(opacity: Double, content: ProjectedLayerContent) {
        precondition((0 ... 1).contains(opacity))
        self.opacity = opacity
        self.content = switch content {
            case let .flights(marks): .flights(retainingLastMarkByIdentity(marks))
            case let .stars(marks): .stars(retainingLastMarkByIdentity(marks))
            case let .satellites(marks): .satellites(retainingLastMarkByIdentity(marks))
            case let .transitVehicles(marks):
                .transitVehicles(retainingLastMarkByIdentity(marks))
            case .geography, .transitNetwork:
                content
            #if DEBUG
                case let .testingMarks(layerID, marks):
                    .testingMarks(
                        layerID: layerID,
                        marks: retainingLastMarkByIdentity(marks),
                    )
            #endif
        }
    }

    var id: LayerID {
        switch content {
            case .geography: .geography
            case .flights: .flights
            case .stars: .stars
            case .satellites: .satellites
            case .transitNetwork: .transitNetwork
            case .transitVehicles: .transitVehicles
            #if DEBUG
                case let .testingMarks(layerID, _): layerID
            #endif
        }
    }

    var zOrder: Int {
        id.projectionZOrder
    }

    var marks: [PresentedMark] {
        switch content {
            case let .flights(marks): marks.map(PresentedMark.init)
            case let .stars(marks): marks.map(PresentedMark.init)
            case let .satellites(marks): marks.map(PresentedMark.init)
            case let .transitVehicles(marks): marks.map(PresentedMark.init)
            case .geography, .transitNetwork: []
            #if DEBUG
                case let .testingMarks(_, marks): marks.map(PresentedMark.init)
            #endif
        }
    }

    var lines: PresentedLineCollection? {
        switch content {
            case let .geography(lines): .geography(lines)
            case let .transitNetwork(lines): .transitNetwork(lines)
            case .flights, .stars, .satellites, .transitVehicles: nil
            #if DEBUG
                case .testingMarks: nil
            #endif
        }
    }

    fileprivate func replacingOpacity(_ opacity: Double) -> Self {
        Self(opacity: opacity, content: content)
    }
}

enum PresentedLineCollection: Hashable {
    case geography(ProjectedGeography)
    case transitNetwork(ProjectedLineCollection<TransitNetworkLineStyle>)

    var id: ProjectionLineRevisionID {
        switch self {
            case let .geography(lines): lines.id
            case let .transitNetwork(lines): lines.id
        }
    }
}

private struct PresentedMarkLayer<Element: ProjectionMarkElement>: Hashable {
    let opacity: Double
    let marks: [ThrowCore.ProjectedMark<Element>]

    init(opacity: Double, marks: [ThrowCore.ProjectedMark<Element>]) {
        precondition((0 ... 1).contains(opacity))
        self.opacity = opacity
        self.marks = retainingLastMarkByIdentity(marks)
    }
}

private struct PresentedLineLayer<Style: ProjectionLineStyle>: Hashable {
    let opacity: Double
    let lines: ProjectedLineCollection<Style>

    init(opacity: Double, lines: ProjectedLineCollection<Style>) {
        precondition((0 ... 1).contains(opacity))
        self.opacity = opacity
        self.lines = lines
    }
}

private enum ProjectionFrameStorage: Hashable {
    case airAndSpaceMap(
        geography: PresentedLineLayer<GeographyLineKind>?,
        flights: PresentedMarkLayer<FlightsMarkElement>?,
        satellites: PresentedMarkLayer<SatelliteMarkElement>?,
    )
    case airAndSpaceTrueSky(
        flights: PresentedMarkLayer<FlightsMarkElement>?,
        stars: PresentedMarkLayer<StarMarkElement>?,
        satellites: PresentedMarkLayer<SatelliteMarkElement>?,
    )
    case transit(
        geography: PresentedLineLayer<GeographyLineKind>?,
        network: PresentedLineLayer<TransitNetworkLineStyle>?,
        vehicles: PresentedMarkLayer<TransitVehicleMarkElement>?,
    )
    #if DEBUG
        case testing(
            experienceID: ProjectionExperienceID,
            mode: ProjectionMode,
            layers: [ProjectedLayer],
        )
    #endif
}

/// The immutable renderer frame after one typed experience is erased for presentation.
public struct ProjectionFrame: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    private let storage: ProjectionFrameStorage
    public let generatedAt: Date

    fileprivate init(storage: ProjectionFrameStorage, generatedAt: Date) {
        self.storage = storage
        self.generatedAt = generatedAt
    }

    public var mode: ProjectionMode {
        switch storage {
            case .airAndSpaceMap, .transit: .map
            case .airAndSpaceTrueSky: .trueSky
            #if DEBUG
                case let .testing(_, mode, _): mode
            #endif
        }
    }

    var layers: [ProjectedLayer] {
        let layers: [ProjectedLayer] = switch storage {
            case let .airAndSpaceMap(geography, flights, satellites):
                [
                    geography.map {
                        ProjectedLayer(opacity: $0.opacity, content: .geography($0.lines))
                    },
                    flights.map {
                        ProjectedLayer(opacity: $0.opacity, content: .flights($0.marks))
                    },
                    satellites.map {
                        ProjectedLayer(opacity: $0.opacity, content: .satellites($0.marks))
                    },
                ].compactMap(\.self)
            case let .airAndSpaceTrueSky(flights, stars, satellites):
                [
                    flights.map {
                        ProjectedLayer(opacity: $0.opacity, content: .flights($0.marks))
                    },
                    stars.map {
                        ProjectedLayer(opacity: $0.opacity, content: .stars($0.marks))
                    },
                    satellites.map {
                        ProjectedLayer(opacity: $0.opacity, content: .satellites($0.marks))
                    },
                ].compactMap(\.self)
            case let .transit(geography, network, vehicles):
                [
                    geography.map {
                        ProjectedLayer(opacity: $0.opacity, content: .geography($0.lines))
                    },
                    network.map {
                        ProjectedLayer(opacity: $0.opacity, content: .transitNetwork($0.lines))
                    },
                    vehicles.map {
                        ProjectedLayer(opacity: $0.opacity, content: .transitVehicles($0.marks))
                    },
                ].compactMap(\.self)
            #if DEBUG
                case let .testing(_, _, layers): layers
            #endif
        }
        return layers.sorted { lhs, rhs in
            if lhs.zOrder == rhs.zOrder {
                lhs.id.rawValue < rhs.id.rawValue
            } else {
                lhs.zOrder < rhs.zOrder
            }
        }
    }

    public var experienceID: ProjectionExperienceID {
        switch storage {
            case .airAndSpaceMap, .airAndSpaceTrueSky: .airAndSpace
            case .transit: .transit
            #if DEBUG
                case let .testing(experienceID, _, _): experienceID
            #endif
        }
    }

    var productionExperienceID: ProjectionExperienceID? {
        switch storage {
            case .airAndSpaceMap, .airAndSpaceTrueSky: .airAndSpace
            case .transit: .transit
            #if DEBUG
                case .testing: nil
            #endif
        }
    }

    public var marks: [PresentedMark] {
        layers.flatMap(\.marks)
    }

    public var geography: ProjectedGeography? {
        switch storage {
            case let .airAndSpaceMap(geography, _, _), let .transit(geography, _, _):
                geography?.lines
            case .airAndSpaceTrueSky:
                nil
            #if DEBUG
                case let .testing(_, _, layers):
                    layers.compactMap { layer in
                        if case let .geography(lines) = layer.content { lines } else { nil }
                    }.first
            #endif
        }
    }

    public var geographyOpacity: Double {
        switch storage {
            case let .airAndSpaceMap(geography, _, _), let .transit(geography, _, _):
                geography?.opacity ?? 1
            case .airAndSpaceTrueSky:
                1
            #if DEBUG
                case let .testing(_, _, layers):
                    layers.first { $0.id == .geography }?.opacity ?? 1
            #endif
        }
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

    /// Changes only presentation fields while the closed storage preserves element families.
    func updatingMarkPresentation(
        fieldsByID: [LayerMarkID: PresentedMarkFields],
        retainedTargetIDs: Set<LayerMarkID>,
        appendedSourceIDs: Set<LayerMarkID>,
        sourceFrame: ProjectionFrame,
        lineLayersFrom lineFrame: ProjectionFrame,
        lineOpacity: Double,
    ) -> ProjectionFrame? {
        precondition((0 ... 1).contains(lineOpacity))
        guard hasSamePresentationCase(as: sourceFrame),
              hasSamePresentationCase(as: lineFrame)
        else {
            return nil
        }
        let newStorage: ProjectionFrameStorage
        switch storage {
            case let .airAndSpaceMap(_, currentFlights, currentSatellites):
                newStorage = .airAndSpaceMap(
                    geography: scaledLineLayer(
                        lineFrame.airAndSpaceMapGeography,
                        by: lineOpacity,
                    ),
                    flights: updatedMarkLayer(
                        currentFlights,
                        sourceMarks: sourceFrame.airAndSpaceMapFlightMarks,
                        presentationID: presentationID,
                        fieldsByID: fieldsByID,
                        retainedTargetIDs: retainedTargetIDs,
                        appendedSourceIDs: appendedSourceIDs,
                    ),
                    satellites: updatedMarkLayer(
                        currentSatellites,
                        sourceMarks: sourceFrame.airAndSpaceMapSatelliteMarks,
                        presentationID: LayerMarkID.satellite,
                        fieldsByID: fieldsByID,
                        retainedTargetIDs: retainedTargetIDs,
                        appendedSourceIDs: appendedSourceIDs,
                    ),
                )
            case let .airAndSpaceTrueSky(currentFlights, currentStars, currentSatellites):
                newStorage = .airAndSpaceTrueSky(
                    flights: updatedMarkLayer(
                        currentFlights,
                        sourceMarks: sourceFrame.airAndSpaceTrueSkyFlightMarks,
                        presentationID: presentationID,
                        fieldsByID: fieldsByID,
                        retainedTargetIDs: retainedTargetIDs,
                        appendedSourceIDs: appendedSourceIDs,
                    ),
                    stars: updatedMarkLayer(
                        currentStars,
                        sourceMarks: sourceFrame.airAndSpaceTrueSkyStarMarks,
                        presentationID: LayerMarkID.star,
                        fieldsByID: fieldsByID,
                        retainedTargetIDs: retainedTargetIDs,
                        appendedSourceIDs: appendedSourceIDs,
                    ),
                    satellites: updatedMarkLayer(
                        currentSatellites,
                        sourceMarks: sourceFrame.airAndSpaceTrueSkySatelliteMarks,
                        presentationID: LayerMarkID.satellite,
                        fieldsByID: fieldsByID,
                        retainedTargetIDs: retainedTargetIDs,
                        appendedSourceIDs: appendedSourceIDs,
                    ),
                )
            case let .transit(_, _, currentVehicles):
                newStorage = .transit(
                    geography: scaledLineLayer(
                        lineFrame.transitGeography,
                        by: lineOpacity,
                    ),
                    network: scaledLineLayer(
                        lineFrame.transitNetwork,
                        by: lineOpacity,
                    ),
                    vehicles: updatedMarkLayer(
                        currentVehicles,
                        sourceMarks: sourceFrame.transitVehicleMarks,
                        presentationID: LayerMarkID.transitVehicle,
                        fieldsByID: fieldsByID,
                        retainedTargetIDs: retainedTargetIDs,
                        appendedSourceIDs: appendedSourceIDs,
                    ),
                )
            #if DEBUG
                case let .testing(experienceID, mode, currentLayers):
                    newStorage = .testing(
                        experienceID: experienceID,
                        mode: mode,
                        layers: updatingTestingPresentation(
                            fieldsByID: fieldsByID,
                            retainedTargetIDs: retainedTargetIDs,
                            appendedSourceIDs: appendedSourceIDs,
                            currentLayers: currentLayers,
                            sourceMarks: sourceFrame.marks,
                            lineLayers: lineFrame.testingLayers,
                            lineOpacity: lineOpacity,
                        ),
                    )
            #endif
        }
        return ProjectionFrame(storage: newStorage, generatedAt: generatedAt)
    }

    func faded(by opacity: Double, as target: ProjectionFrame) -> ProjectionFrame {
        precondition((0 ... 1).contains(opacity))
        precondition(
            hasSamePresentationExperience(as: target),
            "Projection animation cannot fade between different Views",
        )
        let fadedMarks = marks.map { mark in
            PresentedMarkFields(
                point: mark.point,
                label: mark.label,
                secondaryProminence: mark.secondaryProminence,
                orientationDegrees: mark.orientationDegrees,
                opacity: mark.opacity * opacity,
                labelOpacity: mark.labelOpacity,
            )
        }
        let fieldsByID = Dictionary(uniqueKeysWithValues: zip(marks.map(\.id), fadedMarks))
        guard let faded = updatingMarkPresentation(
            fieldsByID: fieldsByID,
            retainedTargetIDs: Set(marks.map(\.id)),
            appendedSourceIDs: [],
            sourceFrame: self,
            lineLayersFrom: self,
            lineOpacity: opacity,
        ) else {
            preconditionFailure("Projection fade must preserve its presentation case")
        }
        return ProjectionFrame(storage: faded.storage, generatedAt: target.generatedAt)
    }

    func removingGeography() -> ProjectionFrame {
        let storage: ProjectionFrameStorage = switch storage {
            case let .airAndSpaceMap(_, flights, satellites):
                .airAndSpaceMap(geography: nil, flights: flights, satellites: satellites)
            case .airAndSpaceTrueSky:
                storage
            case let .transit(_, network, vehicles):
                .transit(geography: nil, network: network, vehicles: vehicles)
            #if DEBUG
                case let .testing(experienceID, mode, layers):
                    .testing(
                        experienceID: experienceID,
                        mode: mode,
                        layers: layers.filter { $0.id != .geography },
                    )
            #endif
        }
        return ProjectionFrame(storage: storage, generatedAt: generatedAt)
    }

    func withoutMarks(generatedAt: Date) -> ProjectionFrame {
        guard let frame = updatingMarkPresentation(
            fieldsByID: [:],
            retainedTargetIDs: [],
            appendedSourceIDs: [],
            sourceFrame: self,
            lineLayersFrom: self,
            lineOpacity: 1,
        ) else {
            preconditionFailure("Removing marks must preserve the presentation case")
        }
        return ProjectionFrame(storage: frame.storage, generatedAt: generatedAt)
    }

    static func emptyAirAndSpace(mode: ProjectionMode, generatedAt: Date) -> ProjectionFrame {
        let projected: ProjectedExperienceFrame = switch mode {
            case .map:
                .airAndSpace(.map(AirAndSpaceMapProjectedFrame(
                    generatedAt: generatedAt,
                    geography: nil,
                    flights: nil,
                    satellites: nil,
                )))
            case .trueSky:
                .airAndSpace(.trueSky(AirAndSpaceTrueSkyProjectedFrame(
                    generatedAt: generatedAt,
                    flights: nil,
                    stars: nil,
                    satellites: nil,
                )))
        }
        return present(projected)
    }

    static func emptyTransit(generatedAt: Date) -> ProjectionFrame {
        present(.transit(TransitProjectedFrame(
            generatedAt: generatedAt,
            geography: nil,
            network: nil,
            vehicles: nil,
        )))
    }

    #if DEBUG
        static func testing(
            experienceID: ProjectionExperienceID,
            mode: ProjectionMode,
            generatedAt: Date,
            layers: [ProjectedLayer],
        ) -> ProjectionFrame {
            precondition(Set(layers.map(\.id)).count == layers.count)
            return ProjectionFrame(
                storage: .testing(
                    experienceID: experienceID,
                    mode: mode,
                    layers: layers,
                ),
                generatedAt: generatedAt,
            )
        }

        static func testing(
            mode: ProjectionMode,
            generatedAt: Date,
            geography: ProjectedGeography?,
            geographyOpacity: Double,
            marks: [PresentedMark],
        ) -> ProjectionFrame {
            precondition((0 ... 1).contains(geographyOpacity))
            let layers = geography.map {
                [ProjectedLayer(opacity: geographyOpacity, content: .geography($0))]
            } ?? []
            let frame = ProjectionFrame(
                storage: .testing(
                    experienceID: .airAndSpace,
                    mode: mode,
                    layers: layers,
                ),
                generatedAt: generatedAt,
            )
            return frame.replacingTestingFixtureMarks(marks)
        }

        static func testing(
            mode: ProjectionMode,
            generatedAt: Date,
            geography: ProjectedGeography?,
            geographyOpacity: Double,
            rawMarks: [TestingProjectedMark],
        ) -> ProjectionFrame {
            testing(
                mode: mode,
                generatedAt: generatedAt,
                geography: geography,
                geographyOpacity: geographyOpacity,
                marks: rawMarks.map(PresentedMark.init),
            )
        }

        private func replacingTestingFixtureMarks(
            _ marks: [PresentedMark],
        ) -> ProjectionFrame {
            guard case let .testing(experienceID, mode, layers) = storage else {
                preconditionFailure("Raw testing marks require a test presentation frame")
            }
            return ProjectionFrame(
                storage: .testing(
                    experienceID: experienceID,
                    mode: mode,
                    layers: makeTestingLayers(
                        marks: marks,
                        currentLayers: layers,
                        lineLayers: layers,
                        lineOpacity: 1,
                    ),
                ),
                generatedAt: generatedAt,
            )
        }
    #endif

    func hasSamePresentationExperience(as other: ProjectionFrame) -> Bool {
        switch (productionExperienceID, other.productionExperienceID) {
            case let (left?, right?):
                left == right
            case (nil, nil):
                experienceID == other.experienceID
            case (.some, nil), (nil, .some):
                false
        }
    }

    func hasSamePresentationCase(as other: ProjectionFrame) -> Bool {
        switch (storage, other.storage) {
            case (.airAndSpaceMap, .airAndSpaceMap),
                 (.airAndSpaceTrueSky, .airAndSpaceTrueSky),
                 (.transit, .transit):
                true
            #if DEBUG
                case let (
                    .testing(leftExperienceID, leftMode, _),
                    .testing(rightExperienceID, rightMode, _)
                ):
                    leftExperienceID == rightExperienceID && leftMode == rightMode
            #endif
            default:
                false
        }
    }
}

extension ProjectionFrame {
    private var airAndSpaceMapGeography: PresentedLineLayer<GeographyLineKind>? {
        guard case let .airAndSpaceMap(geography, _, _) = storage else {
            preconditionFailure("Map Air & Space lines require a map Air & Space frame")
        }
        return geography
    }

    private var airAndSpaceMapFlightMarks: [ThrowCore.ProjectedMark<FlightsMarkElement>] {
        guard case let .airAndSpaceMap(_, flights, _) = storage else {
            preconditionFailure("Map Air & Space marks require a map Air & Space frame")
        }
        return flights?.marks ?? []
    }

    private var airAndSpaceMapSatelliteMarks: [ThrowCore.ProjectedMark<SatelliteMarkElement>] {
        guard case let .airAndSpaceMap(_, _, satellites) = storage else {
            preconditionFailure("Map Air & Space marks require a map Air & Space frame")
        }
        return satellites?.marks ?? []
    }

    private var airAndSpaceTrueSkyFlightMarks: [ThrowCore.ProjectedMark<FlightsMarkElement>] {
        guard case let .airAndSpaceTrueSky(flights, _, _) = storage else {
            preconditionFailure("True Sky marks require a True Sky frame")
        }
        return flights?.marks ?? []
    }

    private var airAndSpaceTrueSkyStarMarks: [ThrowCore.ProjectedMark<StarMarkElement>] {
        guard case let .airAndSpaceTrueSky(_, stars, _) = storage else {
            preconditionFailure("True Sky marks require a True Sky frame")
        }
        return stars?.marks ?? []
    }

    private var airAndSpaceTrueSkySatelliteMarks: [ThrowCore.ProjectedMark<SatelliteMarkElement>] {
        guard case let .airAndSpaceTrueSky(_, _, satellites) = storage else {
            preconditionFailure("True Sky marks require a True Sky frame")
        }
        return satellites?.marks ?? []
    }

    private var transitGeography: PresentedLineLayer<GeographyLineKind>? {
        guard case let .transit(geography, _, _) = storage else {
            preconditionFailure("Transit lines require a Transit frame")
        }
        return geography
    }

    fileprivate var transitNetwork: PresentedLineLayer<TransitNetworkLineStyle>? {
        guard case let .transit(_, network, _) = storage else {
            preconditionFailure("Transit lines require a Transit frame")
        }
        return network
    }

    private var transitVehicleMarks: [ThrowCore.ProjectedMark<TransitVehicleMarkElement>] {
        guard case let .transit(_, _, vehicles) = storage else {
            preconditionFailure("Transit marks require a Transit frame")
        }
        return vehicles?.marks ?? []
    }

    #if DEBUG
        fileprivate var testingLayers: [ProjectedLayer] {
            guard case let .testing(_, _, layers) = storage else {
                preconditionFailure("Testing layers require a test presentation frame")
            }
            return layers
        }
    #endif
}

/// Erases one compiler-checked Core frame into the renderer's heterogeneous layers.
func present(_ frame: ProjectedExperienceFrame) -> ProjectionFrame {
    switch frame {
        case let .airAndSpace(.map(projected)):
            ProjectionFrame(
                storage: .airAndSpaceMap(
                    geography: projected.geography.map {
                        PresentedLineLayer(opacity: 1, lines: $0.lines)
                    },
                    flights: projected.flights.map {
                        PresentedMarkLayer(opacity: 1, marks: $0.marks)
                    },
                    satellites: projected.satellites.map {
                        PresentedMarkLayer(opacity: 1, marks: $0.marks)
                    },
                ),
                generatedAt: projected.generatedAt,
            )
        case let .airAndSpace(.trueSky(projected)):
            ProjectionFrame(
                storage: .airAndSpaceTrueSky(
                    flights: projected.flights.map {
                        PresentedMarkLayer(opacity: 1, marks: $0.marks)
                    },
                    stars: projected.stars.map {
                        PresentedMarkLayer(opacity: 1, marks: $0.marks)
                    },
                    satellites: projected.satellites.map {
                        PresentedMarkLayer(opacity: 1, marks: $0.marks)
                    },
                ),
                generatedAt: projected.generatedAt,
            )
        case let .transit(projected):
            ProjectionFrame(
                storage: .transit(
                    geography: projected.geography.map {
                        PresentedLineLayer(opacity: 1, lines: $0.lines)
                    },
                    network: projected.network.map {
                        PresentedLineLayer(opacity: 1, lines: $0.lines)
                    },
                    vehicles: projected.vehicles.map {
                        PresentedMarkLayer(opacity: 1, marks: $0.marks)
                    },
                ),
                generatedAt: projected.generatedAt,
            )
    }
}

#if DEBUG
    /// Keeps raw test projection erasure at the same boundary as production erasure.
    func testingGeographyLayer(_ lines: ProjectedGeography) -> ProjectedLayer {
        ProjectedLayer(opacity: 1, content: .geography(lines))
    }

    /// Keeps raw test projection erasure at the same boundary as production erasure.
    func testingTransitNetworkLayer(
        _ lines: ProjectedLineCollection<TransitNetworkLineStyle>,
    ) -> ProjectedLayer {
        ProjectedLayer(opacity: 1, content: .transitNetwork(lines))
    }

    /// Keeps heterogeneous raw test marks inside the DEBUG presentation case.
    func testingMarkLayers(_ marks: [TestingProjectedMark]) -> [ProjectedLayer] {
        Dictionary(grouping: marks, by: \.id.layerID).map { layerID, marks in
            ProjectedLayer(
                opacity: 1,
                content: .testingMarks(layerID: layerID, marks: marks),
            )
        }
    }
#endif

private func updatedMarkLayer<Element: ProjectionMarkElement>(
    _ current: PresentedMarkLayer<Element>?,
    sourceMarks: [ThrowCore.ProjectedMark<Element>],
    presentationID: (Element.ID) -> LayerMarkID,
    fieldsByID: [LayerMarkID: PresentedMarkFields],
    retainedTargetIDs: Set<LayerMarkID>,
    appendedSourceIDs: Set<LayerMarkID>,
) -> PresentedMarkLayer<Element>? {
    var marks = (current?.marks ?? []).compactMap { mark -> ThrowCore.ProjectedMark<Element>? in
        let id = presentationID(mark.id)
        guard retainedTargetIDs.contains(id) else { return nil }
        return fieldsByID[id].map { replacingFields(mark, with: $0) } ?? mark
    }
    var retainedIDs = Set(marks.map { presentationID($0.id) })
    marks.append(contentsOf: sourceMarks.compactMap { mark in
        let id = presentationID(mark.id)
        guard appendedSourceIDs.contains(id), retainedIDs.insert(id).inserted else { return nil }
        return fieldsByID[id].map { replacingFields(mark, with: $0) } ?? mark
    })
    guard current != nil || marks.isEmpty == false else { return nil }
    return PresentedMarkLayer(opacity: current?.opacity ?? 1, marks: marks)
}

private func scaledLineLayer<Style: ProjectionLineStyle>(
    _ layer: PresentedLineLayer<Style>?,
    by opacity: Double,
) -> PresentedLineLayer<Style>? {
    layer.map { PresentedLineLayer(opacity: $0.opacity * opacity, lines: $0.lines) }
}

#if DEBUG
    private func updatingTestingPresentation(
        fieldsByID: [LayerMarkID: PresentedMarkFields],
        retainedTargetIDs: Set<LayerMarkID>,
        appendedSourceIDs: Set<LayerMarkID>,
        currentLayers: [ProjectedLayer],
        sourceMarks: [PresentedMark],
        lineLayers: [ProjectedLayer],
        lineOpacity: Double,
    ) -> [ProjectedLayer] {
        var marks = currentLayers.flatMap(\.marks).compactMap { mark -> PresentedMark? in
            guard retainedTargetIDs.contains(mark.id) else { return nil }
            return fieldsByID[mark.id].map { mark.replacing(with: $0) } ?? mark
        }
        var retainedIDs = Set(marks.map(\.id))
        marks.append(contentsOf: sourceMarks.compactMap { mark in
            guard appendedSourceIDs.contains(mark.id), retainedIDs.insert(mark.id).inserted
            else { return nil }
            return fieldsByID[mark.id].map { mark.replacing(with: $0) } ?? mark
        })
        return makeTestingLayers(
            marks: marks,
            currentLayers: currentLayers,
            lineLayers: lineLayers,
            lineOpacity: lineOpacity,
        )
    }

    private func makeTestingLayers(
        marks: [PresentedMark],
        currentLayers: [ProjectedLayer],
        lineLayers: [ProjectedLayer],
        lineOpacity: Double,
    ) -> [ProjectedLayer] {
        let flights = marks.compactMap(\.flightsMark)
        let stars = marks.compactMap(\.starMark)
        let satellites = marks.compactMap(\.satelliteMark)
        let transitVehicles = marks.compactMap(\.transitVehicleMark)
        let testingByLayer = Dictionary(
            grouping: marks.compactMap(\.testingMark),
            by: { $0.id.layerID },
        )
        var replacedLayerIDs: Set<LayerID> = []
        var result = currentLayers.compactMap { layer -> ProjectedLayer? in
            let content: ProjectedLayerContent
            switch layer.content {
                case .flights: content = .flights(flights)
                case .stars: content = .stars(stars)
                case .satellites: content = .satellites(satellites)
                case .transitVehicles: content = .transitVehicles(transitVehicles)
                case .geography, .transitNetwork: return nil
                case let .testingMarks(layerID, _):
                    content = .testingMarks(
                        layerID: layerID,
                        marks: testingByLayer[layerID] ?? [],
                    )
            }
            replacedLayerIDs.insert(layer.id)
            return ProjectedLayer(opacity: layer.opacity, content: content)
        }

        func appendIfNeeded(_ id: LayerID, _ content: ProjectedLayerContent, isEmpty: Bool) {
            guard isEmpty == false, replacedLayerIDs.contains(id) == false else { return }
            result.append(ProjectedLayer(opacity: 1, content: content))
        }
        appendIfNeeded(.flights, .flights(flights), isEmpty: flights.isEmpty)
        appendIfNeeded(.stars, .stars(stars), isEmpty: stars.isEmpty)
        appendIfNeeded(.satellites, .satellites(satellites), isEmpty: satellites.isEmpty)
        appendIfNeeded(
            .transitVehicles,
            .transitVehicles(transitVehicles),
            isEmpty: transitVehicles.isEmpty,
        )
        for (layerID, testingMarks) in testingByLayer
            where replacedLayerIDs.contains(layerID) == false
        {
            result.append(ProjectedLayer(
                opacity: 1,
                content: .testingMarks(layerID: layerID, marks: testingMarks),
            ))
        }
        result.append(contentsOf: lineLayers.compactMap { layer in
            switch layer.content {
                case .geography, .transitNetwork:
                    layer.replacingOpacity(layer.opacity * lineOpacity)
                case .flights, .stars, .satellites, .transitVehicles, .testingMarks:
                    nil
            }
        })
        return result
    }
#endif

private func retainingLastMarkByIdentity<Element: ProjectionMarkElement>(
    _ marks: [ThrowCore.ProjectedMark<Element>],
) -> [ThrowCore.ProjectedMark<Element>] {
    var result: [ThrowCore.ProjectedMark<Element>] = []
    result.reserveCapacity(marks.count)
    var indexByID: [Element.ID: Int] = [:]
    indexByID.reserveCapacity(marks.count)
    for mark in marks {
        if let index = indexByID[mark.id] {
            result[index] = mark
        } else {
            indexByID[mark.id] = result.count
            result.append(mark)
        }
    }
    return result
}
