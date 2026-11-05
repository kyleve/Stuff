import Foundation
import RegionKit

/// One consistent read of visible observations and their attribution revisions.
/// Revisions include tombstones so review equality detects changes whose
/// resulting presence happens to be unchanged.
public struct LocationHistoryProjection: Hashable, Sendable {
    public enum Contract: Hashable, Sendable {
        case foundation
        case recording(RecordingHistorySelection)
    }

    public let samples: [AttributedLocationSample]
    public let revisions: [SampleAttributionRevision]
    public let contract: Contract

    public var rawSamples: [LocationSample] {
        samples.map(\.sample)
    }

    public init(samples: [AttributedLocationSample], revisions: [SampleAttributionRevision]) {
        self.init(samples: samples, revisions: revisions, contract: .foundation)
    }

    public init(
        samples: [AttributedLocationSample],
        revisions: [SampleAttributionRevision],
        contract: Contract,
    ) {
        self.samples = samples
        self.revisions = revisions
        self.contract = contract
    }

    /// Group specific GPS geography only after source selection. Foundation and user-asserted
    /// samples retain their existing attribution contract.
    public func reportingSamples(primaryRegions: Set<Region>) -> [AttributedLocationSample] {
        switch contract {
            case .foundation: samples
            case .recording:
                samples.map { entry in
                    guard entry.sample.source.isGPS else { return entry }
                    return entry.replacingRegions(Set(entry.regions.map {
                        primaryRegions.contains($0) ? $0 : .other
                    }))
                }
        }
    }
}
