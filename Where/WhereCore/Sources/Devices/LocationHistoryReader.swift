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

    /// Join reviewed photo days and GPS corrections after applying device cutoffs.
    /// Time-bounded raw reads retain each point's original capture instant.
    public func projection(
        in interval: DateInterval,
        attributor: any RegionAttributing,
        calendar: Calendar = .current,
    ) async throws -> LocationHistoryProjection {
        try await store.readSnapshot {
            let attribution = try await attributionSnapshot(attributor)
            guard interval.duration > 0 else { return LocationHistoryProjection(
                samples: [],
                revisions: [],
            ) }
            let first = CalendarDay(from: interval.start, in: calendar)
            let endDay = CalendarDay(from: interval.end, in: calendar)
            let last = interval.end == endDay.startOfDay(in: calendar) ? endDay
                .adding(days: -1) : endDay
            let photo = try await store.photoSamples(on: first ... last)
            let timed = try await samples(in: interval).filter { $0.source.photoAttribution == nil }
            let visible = (timed + photo)
                .sorted { lhs, rhs in
                    if lhs.timestamp != rhs.timestamp {
                        return lhs.timestamp < rhs.timestamp
                    }
                    return lhs.id.uuidString < rhs.id.uuidString
                }
            let revisions = try await store.sampleAttributionRevisions(for: Set(visible.map(\.id)))
                .sorted { $0.id < $1.id }
            var winners: [UUID: SampleAttributionRevision] = [:]
            for revision in revisions {
                if let current = winners[revision.sampleID],
                   !SampleAttributionRevision.newer(revision, than: current)
                {
                    continue
                }
                winners[revision.sampleID] = revision
            }
            return LocationHistoryProjection(
                samples: visible.map { sample in
                    let replacement = sample.source.isGPS
                        ? winners[sample.id]?.replacementRegions : nil
                    return AttributedLocationSample(
                        sample: sample,
                        regions: replacement ??
                            [sample.source.photoAttribution?.region ?? attribution
                                .region(at: sample.coordinate)],
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
