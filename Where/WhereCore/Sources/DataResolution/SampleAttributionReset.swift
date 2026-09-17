import Foundation

/// Writes reset tombstones, joining the caller’s transaction when resetting a day.
enum SampleAttributionReset {
    static func write(sampleIDs: Set<UUID>, store: any WhereStore, now: Date) async throws {
        try await store.performInCurrentGeneration {
            let revisions = try await store.sampleAttributionRevisions(for: sampleIDs)
            var winners: [UUID: SampleAttributionRevision] = [:]
            for revision in revisions {
                if let current = winners[revision.sampleID],
                   !SampleAttributionRevision.newer(revision, than: current) { continue }
                winners[revision.sampleID] = revision
            }
            // A correction can still be waiting to sync even when no local
            // replacement is active. Every reset advances each requested register.
            for sampleID in sampleIDs {
                let updatedAt = winners[sampleID].map {
                    max(now, $0.updatedAt.addingTimeInterval(0.001))
                } ?? now
                try await store.addSampleAttributionRevision(.init(
                    id: UUID(),
                    sampleID: sampleID,
                    updatedAt: updatedAt,
                    replacementRegions: nil,
                ))
            }
        }
    }
}
