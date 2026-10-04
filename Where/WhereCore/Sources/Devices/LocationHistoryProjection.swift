import Foundation

/// One consistent read of visible observations and their attribution revisions.
/// Revisions include tombstones so review equality detects changes whose
/// resulting presence happens to be unchanged.
public struct LocationHistoryProjection: Hashable, Sendable {
    public let samples: [AttributedLocationSample]
    public let revisions: [SampleAttributionRevision]

    public var rawSamples: [LocationSample] {
        samples.map(\.sample)
    }

    public init(samples: [AttributedLocationSample], revisions: [SampleAttributionRevision]) {
        self.samples = samples
        self.revisions = revisions
    }
}
