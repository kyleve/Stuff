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
            for revision in winners.values where revision.replacementRegions != nil {
                try await store.addSampleAttributionRevision(.init(
                    id: UUID(),
                    sampleID: revision.sampleID,
                    updatedAt: max(now, revision.updatedAt.addingTimeInterval(0.001)),
                    replacementRegions: nil,
                ))
            }
        }
    }
}
