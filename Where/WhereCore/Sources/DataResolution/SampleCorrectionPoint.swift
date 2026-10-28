import Foundation
import RegionKit

/// One recorded point in a correction review, including excluded raw evidence.
public struct SampleCorrectionPoint: Hashable, Sendable {
    public let sample: LocationSample
    public let regions: Set<Region>

    public init(sample: LocationSample, regions: Set<Region>) {
        self.sample = sample
        self.regions = regions
    }
}
