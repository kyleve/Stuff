import Foundation
import RegionKit

/// Reassesses an exact review inside the store's guarded transaction before
/// appending attribution revisions. A changed review never expands an Apply.
public struct SampleCorrectionCoordinator: Sendable {
    private static let logger = WhereLog.reporting(SampleCorrectionCoordinatorLog.self)
    private let store: any WhereStore
    private let reports: ReportReader
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private let onCommitted: @Sendable () async -> Void

    init(
        store: any WhereStore,
        reports: ReportReader,
        calendar: Calendar,
        now: @escaping @Sendable () -> Date,
        onCommitted: @escaping @Sendable () async -> Void,
    ) {
        self.store = store
        self.reports = reports
        self.calendar = calendar
        self.now = now
        self.onCommitted = onCommitted
    }

    public func review(
        id: DataIssueID,
        year: Int,
        primaryRegions: [Region],
        driftThresholdMeters: Double,
    ) async throws -> GPSCorrectionReview? {
        let reads = try await reports.dataIssueReads(for: year)
        return SampleCorrectionAssessment(attributor: reads.attribution, calendar: calendar)
            .reviews(
                reads: reads,
                primaryRegions: primaryRegions,
                driftThresholdMeters: driftThresholdMeters,
                now: now(),
            ).first { $0.id == id }
    }

    public func apply(_ proposal: SampleCorrectionProposal) async throws
        -> SampleCorrectionApplyResult
    {
        let result: SampleCorrectionApplyResult
        do {
            result = try await store.perform(expectedDataGenerationID: proposal.dataGenerationID) {
                let fresh = try await review(
                    id: proposal.reviewID,
                    year: proposal.day.day.year,
                    primaryRegions: proposal.evidence.primaryRegions,
                    driftThresholdMeters: proposal.evidence.driftThresholdMeters,
                )
                guard let current = fresh?.proposal, current == proposal else {
                    return .stale(fresh)
                }
                let revisions = try await store
                    .sampleAttributionRevisions(for: Set(proposal.edits.map(\.sampleID)))
                for edit in proposal.edits {
                    let prior = revisions.filter { $0.sampleID == edit.sampleID }
                        .max { SampleAttributionRevision.newer($1, than: $0) }
                    let timestamp = max(now(), prior?.updatedAt.addingTimeInterval(0.001) ?? now())
                    try await store.addSampleAttributionRevision(.init(
                        id: UUID(),
                        sampleID: edit.sampleID,
                        updatedAt: timestamp,
                        replacementRegions: edit.replacementRegions,
                    ))
                }
                return .applied
            }
        } catch RecordingPersistenceError.dataGenerationChanged {
            // The review belongs to a retired data world. Show the new world's
            // assessment, which is usually absent after Reset or Replace.
            Self.logger { .reviewInvalidated }
            return try await refreshedReview(for: proposal)
        } catch WhereStoreReadConflictError.changedDuringTransaction {
            Self.logger { .reviewInvalidated }
            return try await refreshedReview(for: proposal)
        }
        if case .applied = result { await onCommitted() }
        return result
    }

    private func refreshedReview(for proposal: SampleCorrectionProposal) async throws
        -> SampleCorrectionApplyResult
    {
        try await .stale(review(
            id: proposal.reviewID,
            year: proposal.day.day.year,
            primaryRegions: proposal.evidence.primaryRegions,
            driftThresholdMeters: proposal.evidence.driftThresholdMeters,
        ))
    }

    /// Reset only the named samples, leaving the immutable history available
    /// for delayed sync. Day-level Reset to GPS additionally clears its override.
    public func reset(sampleIDs: Set<UUID>) async throws {
        guard !sampleIDs.isEmpty else { return }
        try await store.performInCurrentGeneration {
            try await SampleAttributionReset.write(sampleIDs: sampleIDs, store: store, now: now())
        }
        await onCommitted()
    }
}
