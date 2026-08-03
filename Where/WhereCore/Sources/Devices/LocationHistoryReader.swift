import Foundation

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
            async let policyChanges = store.recordingPolicyChanges()
            async let assignmentChanges = store.recordingAssignmentChanges()
            let (resolvedSamples, resolvedPolicyChanges, resolvedAssignmentChanges) = try await (
                samples,
                policyChanges,
                assignmentChanges,
            )
            if resolvedAssignmentChanges.isEmpty == false {
                return RecordingPolicyFilter.visibleSamples(
                    resolvedSamples,
                    assignmentChanges: resolvedAssignmentChanges,
                )
            }
            return RecordingPolicyFilter.visibleSamples(
                resolvedSamples,
                policyChanges: resolvedPolicyChanges,
            )
        }
    }
}
