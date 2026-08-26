import Foundation

/// The provider-neutral observations and presentation semantics needed to
/// produce a Flights layer frame.
public struct FlightsLayerInput: Sendable {
    public let snapshot: AircraftSnapshot
    public let observer: ObserverPosition
    public let labelMode: FlightLabelMode
    public let routeResults: [FlightCallsign: FlightRouteResult]
    public let availability: MarkAvailability

    public init(
        snapshot: AircraftSnapshot,
        observer: ObserverPosition,
        labelMode: FlightLabelMode,
        routeResults: [FlightCallsign: FlightRouteResult],
        availability: MarkAvailability,
    ) {
        self.snapshot = snapshot
        self.observer = observer
        self.labelMode = labelMode
        self.routeResults = routeResults
        self.availability = availability
    }
}

/// The typed runtime for the enabled Flights catalog entry.
public struct FlightsLayerRuntime: ProjectionLayerRuntime {
    private let frameBuilder: FlightLayerFrameBuilder

    public init(typeCatalog: AircraftTypeCatalog, airportCatalog: AirportCatalog) {
        frameBuilder = FlightLayerFrameBuilder(
            visualClassifier: AircraftVisualClassifier(catalog: typeCatalog),
            activityClassifier: FlightActivityClassifier(airportCatalog: airportCatalog),
        )
    }

    public func frame(for input: FlightsLayerInput) async throws -> LayerFrame {
        try frameBuilder.frame(
            snapshot: input.snapshot,
            observer: input.observer,
            labelMode: input.labelMode,
            routeResults: input.routeResults,
            availability: input.availability,
        )
    }
}
