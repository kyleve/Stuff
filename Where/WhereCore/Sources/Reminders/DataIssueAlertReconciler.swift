import Foundation
import PeriscopeCore

/// Owns the "you have issues to resolve" notification intent and the
/// reconciliation that keeps that notification in sync with the current year's
/// unresolved data-issue count. Mirrors `DailySummaryReconciler`: the schedule
/// re-runs on launch/foreground and after every committed write, so the alert
/// appears once issues exist and clears the moment the last one is resolved or
/// dismissed.
public actor DataIssueAlertReconciler {
    private let scheduler: any DataIssueAlertScheduling
    private let scanner: DataIssueScanner
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    private var config = Configuration()

    private struct Configuration {
        var enabled = false
        var time: ReminderTime = .defaultEvening
        var driftThresholdMeters = Double(DriftThreshold.default.rawValue)
    }

    private static let logger = WhereLog.reminders(DataIssueAlertReconcilerLog.self)

    init(
        scheduler: any DataIssueAlertScheduling,
        scanner: DataIssueScanner,
        calendar: Calendar,
        now: @escaping @Sendable () -> Date,
    ) {
        self.scheduler = scheduler
        self.scanner = scanner
        self.calendar = calendar
        self.now = now
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
        if enabled {
            _ = await scheduler.requestAuthorization()
        }
        await reconcile()
    }

    /// Recompute the current-year unresolved-issue count and push it to the
    /// scheduler: schedule the alert while issues remain (and the user has it
    /// enabled), clear it otherwise.
    func reconcile() async {
        guard config.enabled else {
            await scheduler.reconcile(enabled: false, time: config.time, body: "")
            return
        }

        let year = calendar.component(.year, from: now())
        do {
            let count = try await scanner.currentIssueCount(
                year: year,
                driftThresholdMeters: config.driftThresholdMeters,
            )
            await scheduler.reconcile(
                enabled: count > 0,
                time: config.time,
                body: Self.body(count: count),
            )
        } catch {
            Self.logger(attachments: [.error(error, name: "reconcile-error")]) {
                .reconcileFailed(description: error.localizedDescription)
            }
        }
    }

    /// The alert body, pluralized on the issue count (e.g. "1 issue to resolve"
    /// / "3 issues to resolve").
    private static func body(count: Int) -> String {
        String(localized: .dataIssuesNotificationBody(count))
    }
}
