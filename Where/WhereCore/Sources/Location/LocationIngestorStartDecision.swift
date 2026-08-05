import Foundation

/// Pure branch after ``LocationIngestor``'s `LocationSource.start()` await.
///
/// Maps to the re-entrancy boundary in
/// [`TrackingReconciliation`](../../Specifications/TrackingReconciliation/README.md):
/// if `stop()` clears `isMonitoring` while start is parked, setup must not continue.
public enum LocationIngestorStartDecision: Sendable, Hashable {
    /// `stop()` ran during the await; leave the ingestor off.
    case abortMonitoringStoppedDuringAwait
    /// Monitoring is still wanted; run backlog drain and attach the sample stream.
    case completeSetup
}

public enum LocationIngestorStart {
    public static func afterLocationSourceStart(isMonitoring: Bool)
        -> LocationIngestorStartDecision
    {
        isMonitoring ? .completeSetup : .abortMonitoringStoppedDuringAwait
    }
}
