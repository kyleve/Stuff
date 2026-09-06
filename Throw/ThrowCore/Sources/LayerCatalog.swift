import Foundation

public enum LayerAvailability: Hashable, Sendable {
    case enabled
    case disabled
    case planned
}

/// A typed producer of semantic layer frames.
public protocol ProjectionLayerRuntime: Sendable {
    associatedtype Input: Sendable
    associatedtype Layer: ProjectionLayerKind

    func frame(for input: Input) async throws -> ProjectionLayerFrame<Layer>
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
        availability: LayerAvailability,
        runtimeFactory: LayerRuntimeFactory<Runtime>,
    ) {
        id = Runtime.Layer.id
        self.availability = availability
        supportedModes = Runtime.Layer.supportedModes
        zOrder = Runtime.Layer.zOrder
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
            availability: LayerAvailability.enabled,
            runtimeFactory: flightsFactory,
        )
        let geography = LayerDescriptor(
            availability: LayerAvailability.enabled,
            runtimeFactory: geographyFactory,
        )
        let stars = LayerDescriptor(
            availability: LayerAvailability.planned,
            runtimeFactory: LayerRuntimeFactory {
                EmptyLayerRuntime<StarsLayerKind>()
            },
        )
        let satellites = LayerDescriptor(
            availability: LayerAvailability.planned,
            runtimeFactory: LayerRuntimeFactory {
                EmptyLayerRuntime<SatellitesLayerKind>()
            },
        )
        let transitNetwork = LayerDescriptor(
            availability: LayerAvailability.planned,
            runtimeFactory: LayerRuntimeFactory {
                EmptyLayerRuntime<TransitNetworkLayerKind>()
            },
        )
        let transitVehicles = LayerDescriptor(
            availability: LayerAvailability.planned,
            runtimeFactory: LayerRuntimeFactory {
                EmptyLayerRuntime<TransitVehiclesLayerKind>()
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

private struct EmptyLayerRuntime<Layer: ProjectionLayerKind>: ProjectionLayerRuntime {
    func frame(for date: Date) async throws -> ProjectionLayerFrame<Layer> {
        .empty(observedAt: date)
    }
}
