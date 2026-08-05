import Foundation

/// Side effects the orchestrator schedules; a production runner would map each
/// case to `await services.<collaborator>.…`.
///
/// Prototype-only — not wired into `WhereServices`. See
/// ``ServicesMachine/README.md``.
enum ServiceEffect: Equatable {
    // Tracking (`TrackingReconciliation`)
    case persistTrackingDesired(Bool)
    case startIngestor
    case stopIngestor
    case publishTracking(Bool)

    // Post-write (`PostWriteReconcile`)
    case beginStorePerform
    case commitStoreWrite
    case invalidateIssueScanner
    case reconcileReminders
    case reconcileIssueAlerts
    case publishWidgets
    case publishWidgetsAfterIngest(LocationSample)
    case pingStoreChanges

    // Ingestor quiesce (`IngestorQuiesce`)
    case beginIngestorQuiesce
    case completeIngestorQuiesce

    // Launch (`LaunchLifecycle`)
    case syncAuthorization
    case reconcileTracking
    case captureTodayIfNeeded
    case applyReminderConfiguration
    case applySummaryConfiguration
    case applyIssueAlertConfiguration
    case refreshWidgetSnapshot

    // Reset (cross-machine)
    case eraseAllData
    case invalidateIssueScannerAfterReset
}
