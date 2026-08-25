import Foundation

/// The provider-neutral observations and presentation semantics needed to
/// produce a Flights layer frame.
public struct FlightsLayerInput: Sendable {
    public let snapshot: AircraftSnapshot
    public let observer: ObserverPosition
    public let labelMode: FlightLabelMode

    public init(
        snapshot: AircraftSnapshot,
        observer: ObserverPosition,
        labelMode: FlightLabelMode,
    ) {
        self.snapshot = snapshot
        self.observer = observer
        self.labelMode = labelMode
    }
}

/// The typed runtime for the enabled Flights catalog entry.
public struct FlightsLayerRuntime: ProjectionLayerRuntime {
    private let frameBuilder: FlightLayerFrameBuilder

    public init() {
        frameBuilder = FlightLayerFrameBuilder()
    }

    public func frame(for input: FlightsLayerInput) async throws -> LayerFrame {
        try frameBuilder.frame(
            snapshot: input.snapshot,
            observer: input.observer,
            labelMode: input.labelMode,
        )
    }
}
