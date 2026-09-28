import Foundation

/// Platform scheduling boundary for automatic backups. The app target backs
/// this with `BGTaskScheduler`; Core and tests can inject a no-op or spy.
public protocol AutomaticBackupTaskScheduling: Sendable {
    func reconcile(isEnabled: Bool, earliestBeginDate: Date?) async
}

public struct NoopAutomaticBackupTaskScheduler: AutomaticBackupTaskScheduling {
    public init() {}

    public func reconcile(isEnabled _: Bool, earliestBeginDate _: Date?) async {}
}
