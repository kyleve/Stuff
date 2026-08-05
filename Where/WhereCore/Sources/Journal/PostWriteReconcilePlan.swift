import Foundation

/// What kind of store write just committed — drives the post-write fan-out plan in
/// [`PostWriteReconcile`](../../Specifications/PostWriteReconcile/README.md).
public enum PostWriteOutcome: Equatable, Sendable {
    /// A single GPS sample append (live ingest or manual sample).
    case sampleIngest(LocationSample)
    /// Persisted day-level data changed (manual day, bulk ingest, clears, import).
    case dayDataChanged
    /// Issue dismiss/restore — recount badge/notification only.
    case issueOnly
}

/// One step in the sequential fan-out after a committed write.
public enum ReconcileStep: Equatable, Sendable {
    case invalidateIssues
    case reconcileReminders
    case reconcileIssueAlerts
    case publishWidgets
    case publishWidgetsAfterIngest(LocationSample)
}

/// Declarative post-write pipeline derived from ``PostWriteOutcome``.
///
/// Execution stays in ``DayJournal``; this type is the digest the TLA
/// `reconcilePhase` sequence maps to.
public struct PostWriteReconcilePlan: Equatable, Sendable {
    public let steps: [ReconcileStep]

    public init(steps: [ReconcileStep]) {
        self.steps = steps
    }

    public static func forOutcome(_ outcome: PostWriteOutcome) -> PostWriteReconcilePlan {
        let issueSteps: [ReconcileStep] = [
            .invalidateIssues,
            .reconcileReminders,
            .reconcileIssueAlerts,
        ]
        switch outcome {
            case .issueOnly:
                return PostWriteReconcilePlan(steps: issueSteps)
            case let .sampleIngest(sample):
                return PostWriteReconcilePlan(steps: issueSteps +
                    [.publishWidgetsAfterIngest(sample)])
            case .dayDataChanged:
                return PostWriteReconcilePlan(steps: issueSteps + [.publishWidgets])
        }
    }
}
