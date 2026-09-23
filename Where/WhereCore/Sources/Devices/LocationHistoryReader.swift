import Foundation
import RegionKit

/// Shared policy-aware read path for every user-facing projection of location
/// history. The store remains a raw, lossless persistence boundary; this reader
/// applies the effective device cutoffs before data reaches reports or widgets.
public struct LocationHistoryReader: Sendable {
    private let store: any WhereStore

    public init(store: any WhereStore) {
        self.store = store
    }

    public func samples(in interval: DateInterval) async throws -> [LocationSample] {
        try await store.readSnapshot {
            async let samples = store.samples(in: interval)
            async let removals = store.recordingDeviceRemovals()
            let (resolvedSamples, resolvedRemovals) = try await (
                samples,
                removals,
            )
            return RecordingDeviceRemovalFilter.visibleSamples(
                resolvedSamples,
                removals: resolvedRemovals,
            )
        }
    }

    /// Join corrections after applying device cutoffs. Store and trajectory reads
    /// remain lossless; only the region attribution changes.
    public func projection(
        in interval: DateInterval,
        attributor: any RegionAttributing,
    ) async throws -> LocationHistoryProjection {
        try await store.readSnapshot {
            let attribution = try await attributionSnapshot(attributor)
            let visible = try await samples(in: interval)
                .sorted { lhs, rhs in
                    if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
                    return lhs.id.uuidString < rhs.id.uuidString
                }
            let revisions = try await store.sampleAttributionRevisions(for: Set(visible.map(\.id)))
                .sorted { $0.id.uuidString < $1.id.uuidString }
            var winners: [UUID: SampleAttributionRevision] = [:]
            for revision in revisions {
                if let current = winners[revision.sampleID],
                   !SampleAttributionRevision.newer(revision, than: current) { continue }
                winners[revision.sampleID] = revision
            }
            return LocationHistoryProjection(
                samples: visible.map { sample in
                    let replacement = sample.source.isGPS
                        ? winners[sample.id]?.replacementRegions : nil
                    return AttributedLocationSample(
                        sample: sample,
                        regions: replacement ?? [attribution.region(at: sample.coordinate)],
                    )
                },
                revisions: revisions,
            )
        }
    }

    func attributionSnapshot(_ attributor: any RegionAttributing) async throws
        -> any RegionAttributing
    {
        if let live = attributor as? RegionAttribution {
            return try await live.snapshot(for: store.trackedRegions())
        }
        return attributor
    }
}
