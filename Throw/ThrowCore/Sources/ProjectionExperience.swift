import Foundation

/// A stable identity for one user-facing projection View.
public enum ProjectionExperienceID: String, CaseIterable, Hashable, Sendable {
    case airAndSpace = "air-and-space"
    case transit

    #if DEBUG
        case testing = "testing"
    #endif

    #if DEBUG
        @_spi(Testing)
        public init?(testingRawValue rawValue: String) {
            let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalized.isEmpty == false else { return nil }
            self = .testing
        }
    #endif

    fileprivate var standardDescriptor: ProjectionExperienceDescriptor? {
        switch self {
            case .airAndSpace:
                ProjectionExperienceDescriptor(
                    id: self,
                    availability: .enabled,
                    supportedModes: [.map, .trueSky],
                    layerIDs: [.geography, .flights, .stars, .satellites],
                    visibleContentKind: .aircraft,
                    zOrder: 0,
                )
            case .transit:
                ProjectionExperienceDescriptor(
                    id: self,
                    availability: .planned,
                    supportedModes: [.map],
                    layerIDs: [.geography, .transitNetwork, .transitVehicles],
                    visibleContentKind: .vehicles,
                    zOrder: 10,
                )
            #if DEBUG
                case .testing:
                    nil
            #endif
        }
    }
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
        descriptors: ProjectionExperienceID.allCases.compactMap(\.standardDescriptor),
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
