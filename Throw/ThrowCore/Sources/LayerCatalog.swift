import Foundation

public enum LayerAvailability: Hashable, Sendable {
    case enabled
    case disabled(explanation: String)
    case planned(explanation: String)
}

/// A typed producer of semantic layer frames.
public protocol ProjectionLayerRuntime: Sendable {
    associatedtype Input: Sendable

    func frame(for input: Input) async throws -> LayerFrame
}

public struct LayerRuntimeFactory<Runtime: ProjectionLayerRuntime>: Sendable {
    private let makeRuntime: @Sendable () -> Runtime

    public init(makeRuntime: @escaping @Sendable () -> Runtime) {
        self.makeRuntime = makeRuntime
    }

    public func callAsFunction() -> Runtime {
        makeRuntime()
    }
}

public struct LayerDescriptor<Runtime: ProjectionLayerRuntime>: Sendable {
    public let id: LayerID
    public let availability: LayerAvailability
    public let supportedModes: Set<ProjectionMode>
    public let zOrder: Int
    public let runtimeFactory: LayerRuntimeFactory<Runtime>

    public init(
        id: LayerID,
        availability: LayerAvailability,
        supportedModes: Set<ProjectionMode>,
        zOrder: Int,
        runtimeFactory: LayerRuntimeFactory<Runtime>,
    ) {
        precondition(supportedModes.isEmpty == false)
        self.id = id
        self.availability = availability
        self.supportedModes = supportedModes
        self.zOrder = zOrder
        self.runtimeFactory = runtimeFactory
    }
}

/// The sole type-erasure boundary for heterogeneous catalog enumeration.
/// Runtime inputs remain typed everywhere that a runtime is invoked.
public struct AnyLayerRuntimeFactory: Sendable {
    private let makeRuntime: @Sendable () -> any ProjectionLayerRuntime

    public init(_ factory: LayerRuntimeFactory<some Any>) {
        makeRuntime = { factory() }
    }

    public func callAsFunction() -> any ProjectionLayerRuntime {
        makeRuntime()
    }
}

public struct AnyLayerDescriptor: Identifiable, Sendable {
    public let id: LayerID
    public let availability: LayerAvailability
    public let supportedModes: Set<ProjectionMode>
    public let zOrder: Int
    public let runtimeFactory: AnyLayerRuntimeFactory

    public init(_ descriptor: LayerDescriptor<some Any>) {
        id = descriptor.id
        availability = descriptor.availability
        supportedModes = descriptor.supportedModes
        zOrder = descriptor.zOrder
        runtimeFactory = AnyLayerRuntimeFactory(descriptor.runtimeFactory)
    }
}

/// The fixed layer catalog. New layers are source changes, never downloaded
/// runtime plugins.
public struct LayerCatalog: Sendable {
    public static let standard = LayerCatalog(
        flightsFactory: LayerRuntimeFactory {
            FlightsLayerRuntime(typeCatalog: .bundled, airportCatalog: .bundled)
        },
        geographyFactory: LayerRuntimeFactory {
            GeographyLayerRuntime(dataSource: BundledGeographyDataSource())
        },
    )

    /// Typed descriptors used to construct the enabled production layers.
    public let flights: LayerDescriptor<FlightsLayerRuntime>
    public let geography: LayerDescriptor<GeographyLayerRuntime>

    /// The heterogeneous catalog used for discovery and presentation only.
    public let descriptors: [AnyLayerDescriptor]

    public init(
        flightsFactory: LayerRuntimeFactory<FlightsLayerRuntime>,
        geographyFactory: LayerRuntimeFactory<GeographyLayerRuntime>,
    ) {
        let flights = LayerDescriptor(
            id: LayerID.flights,
            availability: LayerAvailability.enabled,
            supportedModes: Set([ProjectionMode.map, ProjectionMode.trueSky]),
            zOrder: 100,
            runtimeFactory: flightsFactory,
        )
        let geography = LayerDescriptor(
            id: LayerID.geography,
            availability: LayerAvailability.enabled,
            supportedModes: Set([ProjectionMode.map]),
            zOrder: 0,
            runtimeFactory: geographyFactory,
        )
        let stars = LayerDescriptor(
            id: LayerID.stars,
            availability: LayerAvailability.planned(
                explanation: "Star charts are planned for a future release.",
            ),
            supportedModes: Set([ProjectionMode.trueSky]),
            zOrder: 10,
            runtimeFactory: LayerRuntimeFactory {
                EmptyLayerRuntime(layerID: .stars)
            },
        )
        let satellites = LayerDescriptor(
            id: LayerID.satellites,
            availability: LayerAvailability.planned(
                explanation: "Satellite tracking is planned for a future release.",
            ),
            supportedModes: Set([ProjectionMode.map, ProjectionMode.trueSky]),
            zOrder: 50,
            runtimeFactory: LayerRuntimeFactory {
                EmptyLayerRuntime(layerID: .satellites)
            },
        )
        let transitNetwork = LayerDescriptor(
            id: LayerID.transitNetwork,
            availability: LayerAvailability.planned(
                explanation: "Transit network context is planned for a future release.",
            ),
            supportedModes: Set([ProjectionMode.map]),
            zOrder: 20,
            runtimeFactory: LayerRuntimeFactory {
                EmptyLayerRuntime(layerID: .transitNetwork)
            },
        )
        let transitVehicles = LayerDescriptor(
            id: LayerID.transitVehicles,
            availability: LayerAvailability.planned(
                explanation: "Live transit vehicles are planned for a future release.",
            ),
            supportedModes: Set([ProjectionMode.map]),
            zOrder: 100,
            runtimeFactory: LayerRuntimeFactory {
                EmptyLayerRuntime(layerID: .transitVehicles)
            },
        )

        self.flights = flights
        self.geography = geography
        descriptors = [
            AnyLayerDescriptor(flights),
            AnyLayerDescriptor(geography),
            AnyLayerDescriptor(stars),
            AnyLayerDescriptor(satellites),
            AnyLayerDescriptor(transitNetwork),
            AnyLayerDescriptor(transitVehicles),
        ]
    }
}

private struct EmptyLayerRuntime: ProjectionLayerRuntime {
    let layerID: LayerID

    func frame(for date: Date) async throws -> LayerFrame {
        LayerFrame(layerID: layerID, observedAt: date, content: .marks([]))
    }
}
