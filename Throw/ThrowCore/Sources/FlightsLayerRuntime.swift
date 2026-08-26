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

/// The typed runtime for the enabled Flights catalog entry. Its actor-isolated
/// estimator retains only the consecutive samples needed for smooth motion.
public actor FlightsLayerRuntime: ProjectionLayerRuntime {
    private let frameBuilder: FlightLayerFrameBuilder
    private var motionEstimator = FlightMotionEstimator()

    public init(typeCatalog: AircraftTypeCatalog, airportCatalog: AirportCatalog) {
        frameBuilder = FlightLayerFrameBuilder(
            visualClassifier: AircraftVisualClassifier(catalog: typeCatalog),
            activityClassifier: FlightActivityClassifier(airportCatalog: airportCatalog),
        )
    }

    public func frame(for input: FlightsLayerInput) async throws -> LayerFrame {
        let motions = try motionEstimator.motions(for: input.snapshot)
        return try frameBuilder.frame(
            snapshot: input.snapshot,
            observer: input.observer,
            labelMode: input.labelMode,
            routeResults: input.routeResults,
            motions: motions,
            availability: input.availability,
        )
    }

    /// Clears consecutive-sample motion when a source activation is replaced.
    public func reset() {
        motionEstimator = FlightMotionEstimator()
    }
}
