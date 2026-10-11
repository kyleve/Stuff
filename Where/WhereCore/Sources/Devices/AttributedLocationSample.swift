import Foundation
import RegionKit

/// A raw observation joined to its effective region attribution. An empty
/// set excludes presence without removing the original trajectory evidence.
public struct AttributedLocationSample: Hashable, Sendable {
    public let sample: LocationSample
    public let regions: Set<Region>

    public init(sample: LocationSample, regions: Set<Region>) {
        self.sample = sample
        self.regions = regions
    }

    static func raw(_ samples: [LocationSample], attributor: any RegionAttributing) -> [Self] {
        samples.map { Self(sample: $0, regions: [attributor.region(at: $0.coordinate)]) }
    }
}
