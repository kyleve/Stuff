import Foundation
import PeriscopeCore

/// Owns the "you have issues to resolve" notification intent and the
/// reconciliation that keeps that notification in sync with the all-history
/// unresolved data-issue count. Mirrors `DailySummaryReconciler`: the schedule
/// re-runs on launch/foreground and after every committed write, so the alert
/// appears once issues exist and clears the moment the last one is resolved or
/// dismissed.
public actor DataIssueAlertReconciler {
    private let scheduler: any DataIssueAlertScheduling
    private let scanner: DataIssueScanner

    private var config = Configuration()
    private struct RequestID: Hashable { let value = UUID() }
    private var requestID = RequestID()
    private struct ConfigurationID: Hashable { let value = UUID() }
    private var configurationID = ConfigurationID()

    private struct Configuration {
        var enabled = false
        var time: ReminderTime = .defaultEvening
        var driftThresholdMeters = Double(DriftThreshold.default.rawValue)
    }

    private static let logger = WhereLog.reminders(DataIssueAlertReconcilerLog.self)

    init(
        scheduler: any DataIssueAlertScheduling,
        scanner: DataIssueScanner,
    ) {
        self.scheduler = scheduler
        self.scanner = scanner
    }

    /// Set the user's issue-alert intent (enabled + fire time + the drift
    /// threshold the scan runs at), request notification permission when
    /// enabling, then reconcile. Safe to call on every launch and whenever the
    /// user changes the setting.
    public func configure(enabled: Bool, time: ReminderTime, driftThresholdMeters: Double) async {
        config = Configuration(
            enabled: enabled,
            time: time,
            driftThresholdMeters: driftThresholdMeters,
        )
        let configuration = ConfigurationID()
        configurationID = configuration
        requestID = RequestID()
        if enabled {
            _ = await scheduler.requestAuthorization()
        }
        guard configurationID == configuration, !Task.isCancelled else { return }
        await reconcile()
    }

    /// Recompute the all-history unresolved-issue count and push it to the
    /// scheduler: schedule the alert while issues remain (and the user has it
    /// enabled), clear it otherwise.
    func reconcile() async {
        let request = RequestID()
        requestID = request
        let configuration = config
        await Self.logger.measure(.reconcile, budget: .seconds(8)) {
            guard requestID == request, !Task.isCancelled else { return }
            guard configuration.enabled else {
                await scheduler.reconcile(enabled: false, time: configuration.time, body: "")
                return
            }

            do {
                let result = try await scanner.historicalScan(
                    driftThresholdMeters: configuration.driftThresholdMeters,
                    force: false,
                )
                guard requestID == request, !Task.isCancelled else { return }
                let count = result.issueCount
                await scheduler.reconcile(
                    enabled: count > 0,
                    time: configuration.time,
                    body: Self.body(count: count),
                )
            } catch {
                Self.logger.reconcileFailed(
                    error: .restricted(.errorDetails, error),
                )
            }
        }
    }

    /// The alert body, pluralized on the issue count (e.g. "1 issue to resolve"
    /// / "3 issues to resolve").
    private static func body(count: Int) -> String {
        String(localized: .dataIssuesNotificationBody(count))
    }
}
