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
                ProjectionExperienceDescriptor.standard(
                    availability: .runnable(.airAndSpace),
                    supportedModes: [.map, .trueSky],
                    layerIDs: [.geography, .flights, .stars, .satellites],
                    visibleContentKind: .aircraft,
                    zOrder: 0,
                )
            case .transit:
                ProjectionExperienceDescriptor.standard(
                    availability: .planned(.transit),
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

/// A projection View with a complete production runtime.
public enum RunnableProjectionExperienceID: Hashable, Sendable {
    case airAndSpace

    #if DEBUG
        /// Lets tests exercise multi-View state machines without shipping a runtime.
        case testing(ProjectionExperienceID)
    #endif

    public var experienceID: ProjectionExperienceID {
        switch self {
            case .airAndSpace: .airAndSpace
            #if DEBUG
                case let .testing(id): id
            #endif
        }
    }
}

public enum ProjectionExperienceAvailability: Hashable, Sendable {
    case runnable(RunnableProjectionExperienceID)
    case planned(ProjectionExperienceID)

    public var experienceID: ProjectionExperienceID {
        switch self {
            case let .runnable(id): id.experienceID
            case let .planned(id): id
        }
    }

    public var runnableExperienceID: RunnableProjectionExperienceID? {
        guard case let .runnable(id) = self else { return nil }
        return id
    }
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

    private init(
        availability: ProjectionExperienceAvailability,
        supportedModes: Set<ProjectionMode>,
        layerIDs: [LayerID],
        visibleContentKind: ProjectionExperienceVisibleContentKind,
        zOrder: Int,
    ) {
        precondition(supportedModes.isEmpty == false)
        precondition(layerIDs.isEmpty == false)
        precondition(Set(layerIDs).count == layerIDs.count)
        id = availability.experienceID
        self.availability = availability
        self.supportedModes = supportedModes
        self.layerIDs = layerIDs
        self.visibleContentKind = visibleContentKind
        self.zOrder = zOrder
    }

    fileprivate static func standard(
        availability: ProjectionExperienceAvailability,
        supportedModes: Set<ProjectionMode>,
        layerIDs: [LayerID],
        visibleContentKind: ProjectionExperienceVisibleContentKind,
        zOrder: Int,
    ) -> Self {
        Self(
            availability: availability,
            supportedModes: supportedModes,
            layerIDs: layerIDs,
            visibleContentKind: visibleContentKind,
            zOrder: zOrder,
        )
    }

    #if DEBUG
        @_spi(Testing) public init(
            testingAvailability: ProjectionExperienceAvailability,
            supportedModes: Set<ProjectionMode>,
            layerIDs: [LayerID],
            visibleContentKind: ProjectionExperienceVisibleContentKind,
            zOrder: Int,
        ) {
            self.init(
                availability: testingAvailability,
                supportedModes: supportedModes,
                layerIDs: layerIDs,
                visibleContentKind: visibleContentKind,
                zOrder: zOrder,
            )
        }
    #endif
}

/// The fixed catalog of projection experiences shipped by Throw.
public struct ProjectionExperienceCatalog: Sendable {
    public static let standard = ProjectionExperienceCatalog(
        standardDescriptors: ProjectionExperienceID.allCases.compactMap(\.standardDescriptor),
        layerCatalog: .standard,
    )

    public let descriptors: [ProjectionExperienceDescriptor]

    private init(
        standardDescriptors descriptors: [ProjectionExperienceDescriptor],
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

    #if DEBUG
        @_spi(Testing) public init(
            testingDescriptors: [ProjectionExperienceDescriptor],
            layerCatalog: LayerCatalog,
        ) {
            self.init(
                standardDescriptors: testingDescriptors,
                layerCatalog: layerCatalog,
            )
        }
    #endif

    public subscript(id: ProjectionExperienceID) -> ProjectionExperienceDescriptor? {
        descriptors.first { $0.id == id }
    }

    public func runnableExperienceID(
        for id: ProjectionExperienceID,
    ) -> RunnableProjectionExperienceID? {
        self[id]?.availability.runnableExperienceID
    }
}
