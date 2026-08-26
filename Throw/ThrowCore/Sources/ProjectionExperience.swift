import Foundation

/// A stable identity for one user-facing projection View.
public struct ProjectionExperienceID: Hashable, Sendable {
    public static let airAndSpace = ProjectionExperienceID(uncheckedRawValue: "air-and-space")
    public static let transit = ProjectionExperienceID(uncheckedRawValue: "transit")

    public let rawValue: String

    /// Decodes one of the experience identities compiled into this version of Throw.
    public init?(rawValue: String) {
        switch rawValue {
            case Self.airAndSpace.rawValue:
                self = .airAndSpace
            case Self.transit.rawValue:
                self = .transit
            default:
                return nil
        }
    }

    private init(uncheckedRawValue rawValue: String) {
        self.rawValue = rawValue
    }

    #if DEBUG
        @_spi(Testing)
        public init?(testingRawValue rawValue: String) {
            let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalized.isEmpty == false else { return nil }
            self.init(uncheckedRawValue: normalized)
        }
    #endif
}

public enum ProjectionExperienceAvailability: Hashable, Sendable {
    case enabled
    case planned
}

public enum ProjectionExperienceVisibleContentKind: Hashable, Sendable {
    case aircraft
    case vehicles
    case objects
}

/// Compile-time metadata for one projection experience. It contains no UI values.
public struct ProjectionExperienceDescriptor: Identifiable, Hashable, Sendable {
    public let id: ProjectionExperienceID
    public let availability: ProjectionExperienceAvailability
    public let supportedModes: Set<ProjectionMode>
    public let layerIDs: [LayerID]
    public let visibleContentKind: ProjectionExperienceVisibleContentKind
    public let zOrder: Int

    public init(
        id: ProjectionExperienceID,
        availability: ProjectionExperienceAvailability,
        supportedModes: Set<ProjectionMode>,
        layerIDs: [LayerID],
        visibleContentKind: ProjectionExperienceVisibleContentKind,
        zOrder: Int,
    ) {
        precondition(supportedModes.isEmpty == false)
        precondition(layerIDs.isEmpty == false)
        precondition(Set(layerIDs).count == layerIDs.count)
        self.id = id
        self.availability = availability
        self.supportedModes = supportedModes
        self.layerIDs = layerIDs
        self.visibleContentKind = visibleContentKind
        self.zOrder = zOrder
    }
}

/// The fixed catalog of projection experiences shipped by Throw.
public struct ProjectionExperienceCatalog: Sendable {
    public static let standard = ProjectionExperienceCatalog(
        descriptors: [
            ProjectionExperienceDescriptor(
                id: .airAndSpace,
                availability: .enabled,
                supportedModes: [.map, .trueSky],
                layerIDs: [.geography, .flights, .stars, .satellites],
                visibleContentKind: .aircraft,
                zOrder: 0,
            ),
            ProjectionExperienceDescriptor(
                id: .transit,
                availability: .planned,
                supportedModes: [.map],
                layerIDs: [.geography, .transitNetwork, .transitVehicles],
                visibleContentKind: .vehicles,
                zOrder: 10,
            ),
        ],
        layerCatalog: .standard,
    )

    public let descriptors: [ProjectionExperienceDescriptor]

    public init(
        descriptors: [ProjectionExperienceDescriptor],
        layerCatalog: LayerCatalog,
    ) {
        precondition(descriptors.isEmpty == false)
        precondition(Set(descriptors.map(\.id)).count == descriptors.count)
        let knownLayerIDs = Set(layerCatalog.descriptors.map(\.id))
        precondition(
            descriptors.allSatisfy { Set($0.layerIDs).isSubset(of: knownLayerIDs) },
            "Every experience layer must exist in the layer catalog",
        )
        self.descriptors = descriptors.sorted { lhs, rhs in
            if lhs.zOrder == rhs.zOrder {
                lhs.id.rawValue < rhs.id.rawValue
            } else {
                lhs.zOrder < rhs.zOrder
            }
        }
    }

    public subscript(id: ProjectionExperienceID) -> ProjectionExperienceDescriptor? {
        descriptors.first { $0.id == id }
    }
}
