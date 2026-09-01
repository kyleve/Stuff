import Foundation
import ThrowCore

/// The renderer payload after the typed Core projection crosses into presentation.
public enum ProjectedLayerContent: Hashable, Sendable {
    case marks([ProjectedMark])
    case lines(ProjectedLineCollection)
}

/// A closed presentation identity. DEBUG frames remain distinct from production frames.
enum ProjectionPresentationExperience: Hashable {
    case airAndSpace
    case transit
    #if DEBUG
        case testing(ProjectionExperienceID)
    #endif

    var id: ProjectionExperienceID {
        switch self {
            case .airAndSpace: .airAndSpace
            case .transit: .transit
            #if DEBUG
                case let .testing(id): id
            #endif
        }
    }
}

/// One erased renderer layer. Production construction stays in this file.
public struct ProjectedLayer: Identifiable, Hashable, Sendable {
    public let id: LayerID
    public let zOrder: Int
    public let opacity: Double
    public let content: ProjectedLayerContent

    fileprivate init(
        id: LayerID,
        zOrder: Int,
        opacity: Double,
        content: ProjectedLayerContent,
    ) {
        precondition((0 ... 1).contains(opacity))
        let canonicalContent: ProjectedLayerContent = switch content {
            case let .marks(marks): .marks(retainingLastProjectedMarkByIdentity(marks))
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

    #if DEBUG
        static func testing(
            id: LayerID,
            zOrder: Int,
            opacity: Double,
            content: ProjectedLayerContent,
        ) -> Self {
            Self(id: id, zOrder: zOrder, opacity: opacity, content: content)
        }
    #endif
}

/// The immutable renderer frame after one typed experience is erased for presentation.
public struct ProjectionFrame: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    private let experience: ProjectionPresentationExperience
    public let mode: ProjectionMode
    public let generatedAt: Date
    public let layers: [ProjectedLayer]

    fileprivate init(
        experience: ProjectionPresentationExperience,
        mode: ProjectionMode,
        generatedAt: Date,
        layers: [ProjectedLayer],
    ) {
        precondition(Set(layers.map(\.id)).count == layers.count)
        self.experience = experience
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

    public var experienceID: ProjectionExperienceID {
        experience.id
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

    func replacingMarks(_ marks: [ProjectedMark]) -> ProjectionFrame {
        replacingMarks(marks, lineLayersFrom: self, lineOpacity: 1)
    }

    func replacingMarks(
        _ marks: [ProjectedMark],
        lineLayersFrom lineFrame: ProjectionFrame,
        lineOpacity: Double,
    ) -> ProjectionFrame {
        precondition((0 ... 1).contains(lineOpacity))
        precondition(
            hasSamePresentationExperience(as: lineFrame),
            "Projection animation cannot combine different Views",
        )
        let marksByLayer = Dictionary(grouping: marks, by: \.id.layerID)
        var replacedLayerIDs: Set<LayerID> = []
        var newLayers = layers.compactMap { layer -> ProjectedLayer? in
            guard case .marks = layer.content else { return nil }
            replacedLayerIDs.insert(layer.id)
            return ProjectedLayer(
                id: layer.id,
                zOrder: layer.zOrder,
                opacity: layer.opacity,
                content: .marks(marksByLayer[layer.id] ?? []),
            )
        }
        for (id, layerMarks) in marksByLayer where replacedLayerIDs.contains(id) == false {
            newLayers.append(ProjectedLayer(
                id: id,
                zOrder: Self.standardZOrder(for: id),
                opacity: 1,
                content: .marks(layerMarks),
            ))
        }
        newLayers.append(contentsOf: lineFrame.layers.compactMap { layer in
            guard case let .lines(lines) = layer.content else { return nil }
            return ProjectedLayer(
                id: layer.id,
                zOrder: layer.zOrder,
                opacity: layer.opacity * lineOpacity,
                content: .lines(lines),
            )
        })
        return ProjectionFrame(
            experience: experience,
            mode: mode,
            generatedAt: generatedAt,
            layers: newLayers,
        )
    }

    func faded(by opacity: Double, as target: ProjectionFrame) -> ProjectionFrame {
        precondition((0 ... 1).contains(opacity))
        precondition(
            hasSamePresentationExperience(as: target),
            "Projection animation cannot fade between different Views",
        )
        let fadedMarks = marks.map { mark in
            ProjectedMark(
                id: mark.id,
                point: mark.point,
                range: mark.range,
                glyph: mark.glyph,
                label: mark.label,
                secondaryProminence: mark.secondaryProminence,
                orientationDegrees: mark.orientationDegrees,
                opacity: mark.opacity * opacity,
                labelOpacity: mark.labelOpacity,
                altitudeIsApproximate: mark.altitudeIsApproximate,
            )
        }
        let faded = replacingMarks(fadedMarks, lineLayersFrom: self, lineOpacity: opacity)
        return ProjectionFrame(
            experience: target.experience,
            mode: target.mode,
            generatedAt: target.generatedAt,
            layers: faded.layers,
        )
    }

    func removingGeography() -> ProjectionFrame {
        ProjectionFrame(
            experience: experience,
            mode: mode,
            generatedAt: generatedAt,
            layers: layers.filter { $0.id != .geography },
        )
    }

    func withoutMarks(generatedAt: Date) -> ProjectionFrame {
        let frame = replacingMarks([])
        return ProjectionFrame(
            experience: experience,
            mode: mode,
            generatedAt: generatedAt,
            layers: frame.layers,
        )
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
            ProjectionFrame(
                experience: .testing(experienceID),
                mode: mode,
                generatedAt: generatedAt,
                layers: layers,
            )
        }

        static func testing(
            mode: ProjectionMode,
            generatedAt: Date,
            geography: ProjectedGeography?,
            geographyOpacity: Double,
            marks: [ProjectedMark],
        ) -> ProjectionFrame {
            precondition((0 ... 1).contains(geographyOpacity))
            var layers: [ProjectedLayer] = geography.map {
                [ProjectedLayer(
                    id: .geography,
                    zOrder: Self.standardZOrder(for: .geography),
                    opacity: geographyOpacity,
                    content: .lines($0),
                )]
            } ?? []
            let marksByLayer = Dictionary(grouping: marks, by: \.id.layerID)
            layers.append(contentsOf: marksByLayer.map { id, marks in
                ProjectedLayer(
                    id: id,
                    zOrder: Self.standardZOrder(for: id),
                    opacity: 1,
                    content: .marks(marks),
                )
            })
            return ProjectionFrame(
                experience: .testing(.airAndSpace),
                mode: mode,
                generatedAt: generatedAt,
                layers: layers,
            )
        }
    #endif

    fileprivate static func standardZOrder(for id: LayerID) -> Int {
        id.projectionZOrder
    }

    func hasSamePresentationExperience(as other: ProjectionFrame) -> Bool {
        experience == other.experience
    }
}

/// Erases one compiler-checked Core frame into the renderer's heterogeneous layers.
func present(_ frame: ProjectedExperienceFrame) -> ProjectionFrame {
    switch frame {
        case let .airAndSpace(.map(projected)):
            ProjectionFrame(
                experience: .airAndSpace,
                mode: .map,
                generatedAt: projected.generatedAt,
                layers: [
                    projected.geography.map(present),
                    projected.flights.map(present),
                    projected.satellites.map(present),
                ].compactMap(\.self),
            )
        case let .airAndSpace(.trueSky(projected)):
            ProjectionFrame(
                experience: .airAndSpace,
                mode: .trueSky,
                generatedAt: projected.generatedAt,
                layers: [
                    projected.flights.map(present),
                    projected.stars.map(present),
                    projected.satellites.map(present),
                ].compactMap(\.self),
            )
        case let .transit(projected):
            ProjectionFrame(
                experience: .transit,
                mode: .map,
                generatedAt: projected.generatedAt,
                layers: [
                    projected.geography.map(present),
                    projected.network.map(present),
                    projected.vehicles.map(present),
                ].compactMap(\.self),
            )
    }
}

private func present<Layer: ProjectionMarkLayerKind>(
    _ frame: ProjectedLayerFrame<Layer>,
) -> ProjectedLayer {
    ProjectedLayer(
        id: Layer.id,
        zOrder: Layer.zOrder,
        opacity: 1,
        content: .marks(frame.marks),
    )
}

private func present<Layer: ProjectionLineLayerKind>(
    _ frame: ProjectedLayerFrame<Layer>,
) -> ProjectedLayer {
    ProjectedLayer(
        id: Layer.id,
        zOrder: Layer.zOrder,
        opacity: 1,
        content: .lines(frame.lines),
    )
}

private func retainingLastProjectedMarkByIdentity(_ marks: [ProjectedMark]) -> [ProjectedMark] {
    var result: [ProjectedMark] = []
    result.reserveCapacity(marks.count)
    var indexByID: [LayerMarkID: Int] = [:]
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
