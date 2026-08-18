import RegionKit

/// Checks whether the device is inside a planned region or within the user's
/// configured border-drift tolerance outside it.
public struct PlannedStayLocationVerifier: Sendable {
    public enum Status: Sendable, Equatable {
        case accepted
        case outside
        case unavailable
    }

    private let ingestor: LocationIngestor
    private let attributor: any RegionAttributing

    init(ingestor: LocationIngestor, attributor: any RegionAttributing) {
        self.ingestor = ingestor
        self.attributor = attributor
    }

    /// Returns an advisory status from a best-effort current-location fix.
    /// Horizontal accuracy does not enlarge `driftThreshold`; the configured
    /// threshold alone expands the region outside its boundary.
    public func status(
        for region: Region,
        driftThreshold: DriftThreshold,
    ) async -> Status {
        guard let sample = await ingestor.currentLocation() else { return .unavailable }
        if attributor.region(at: sample.coordinate) == region { return .accepted }
        guard let distance = attributor.distanceToBoundary(
            of: region,
            from: sample.coordinate,
        ) else {
            return .unavailable
        }
        return distance <= driftThreshold.meters ? .accepted : .outside
    }
}
