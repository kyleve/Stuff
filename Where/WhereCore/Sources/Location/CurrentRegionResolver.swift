import RegionKit

/// Resolves the device's current tracked region while automatic recording is authorized.
public struct CurrentRegionResolver: Sendable {
    private let ingestor: LocationIngestor
    private let attributor: any RegionAttributing

    init(ingestor: LocationIngestor, attributor: any RegionAttributing) {
        self.ingestor = ingestor
        self.attributor = attributor
    }

    /// Returns a tracked region from a best-effort live fix, or `nil` when no welcome is valid.
    public func resolve() async -> Region? {
        guard await ingestor.isRecordingAuthorized else { return nil }
        guard let sample = await ingestor.currentLocation(), !Task.isCancelled else { return nil }
        guard await ingestor.isRecordingAuthorized else { return nil }
        let region = attributor.region(at: sample.coordinate)
        return region == .other ? nil : region
    }
}
