import Foundation

/// Writes nil revisions through the same immutable register as corrections.
/// A nested day reset joins its caller's transaction so manual and GPS resets commit together.
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
                let updatedAt = SampleAttributionRevision.nextUpdatedAt(
                    now: now,
                    after: winners[sampleID],
                )
                try await store.addSampleAttributionRevision(.init(
                    id: .init(rawValue: UUID()),
                    sampleID: sampleID,
                    updatedAt: updatedAt,
                    replacementRegions: nil,
                ))
            }
        }
    }
}
