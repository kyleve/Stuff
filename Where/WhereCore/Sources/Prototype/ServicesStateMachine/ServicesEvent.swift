import Foundation

/// External and internal events fed to ``ServicesMachine/reduce(_:_:)``.
///
/// Names mirror the TLA+ specs under `Where/Specifications/` where possible.
enum ServicesEvent: Equatable {
    // User / UI
    case setTrackingDesired(Bool)
    case resetRequested

    // Store writes
    case beginWrite
    case writeCommitted(PostWriteOutcome)

    // Effect completions (what a runner reports back)
    case storePerformCompleted
    case reconcileStepFinished(ReconcileStep)
    case storeChangesPinged
    case readerRefreshed

    case ingestorStartFinished
    case ingestorStopFinished
    case ingestorQuiesceRequested
    case ingestorQuiesceFinished

    /// Coalesced worker rerun (foreground, auth change, launch step).
    case reconcileTrackingRequested

    case launchDriveStarted
    case launchStepFinished(LaunchStep)

    case eraseAllDataFinished

    // Lifecycle
    case appForegrounded
    case authorizationChanged(allowsBackground: Bool)
}

/// Launch steps modeled in ``LaunchMachine`` (maps to `LaunchLifecycle.tla`).
enum LaunchStep: String, Hashable, CaseIterable {
    case syncAuthorization
    case reconcileTracking
    case captureTodayIfNeeded
    case applyReminderConfiguration
    case applySummaryConfiguration
    case applyIssueAlertConfiguration
    case refreshWidgetSnapshot
}
