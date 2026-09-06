import Foundation

public struct TransitVehiclesLayerInput: Sendable {
    public let estimates: [TransitVehicleEstimate]
    public let labelMode: TransitLabelMode
    public let fetchedAt: Date
    public let availability: MarkAvailability

    public init(
        estimates: [TransitVehicleEstimate],
        labelMode: TransitLabelMode,
        fetchedAt: Date,
        availability: MarkAvailability,
    ) {
        self.estimates = estimates
        self.labelMode = labelMode
        self.fetchedAt = fetchedAt
        self.availability = availability
    }
}

public struct TransitNetworkLayerRuntime: ProjectionLayerRuntime {
    private let builder: TransitLayerFrameBuilder

    public init(builder: TransitLayerFrameBuilder) {
        self.builder = builder
    }

    @concurrent public func frame(
        for schedule: TransitSchedule,
    ) async throws -> ProjectionLayerFrame<TransitNetworkLayerKind> {
        try Task.checkCancellation()
        return try builder.networkFrame(schedule: schedule)
    }
}

public struct TransitVehiclesLayerRuntime: ProjectionLayerRuntime {
    private let builder: TransitLayerFrameBuilder

    public init(builder: TransitLayerFrameBuilder) {
        self.builder = builder
    }

    @concurrent public func frame(
        for input: TransitVehiclesLayerInput,
    ) async throws -> ProjectionLayerFrame<TransitVehiclesLayerKind> {
        try Task.checkCancellation()
        return builder.vehiclesFrame(
            estimates: input.estimates,
            labelMode: input.labelMode,
            fetchedAt: input.fetchedAt,
            availability: input.availability,
        )
    }
}
