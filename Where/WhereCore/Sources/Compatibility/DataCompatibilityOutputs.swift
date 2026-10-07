import Foundation

/// Serializes publication with withdrawal, including external scheduler and widget awaits.
/// Every publication rechecks the store; queued work cannot revive outputs after a lockout.
public actor DataCompatibilityOutputs {
    /// Changes before each withdrawal so consumers cannot reuse an earlier publication.
    struct WithdrawalRevision: Equatable {
        private let value = UUID()
    }

    private(set) var withdrawalRevision = WithdrawalRevision()

    private let compatibility: DataCompatibilityCoordinator
    let reminderScheduler: any LoggingReminderScheduling
    let summaryScheduler: any DailySummaryScheduling
    let issueAlertScheduler: any DataIssueAlertScheduling
    let widgetRefresher: any WidgetTimelineRefreshing

    private var isPublishing = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private static let logger = WhereLog.root(DataCompatibilityLog.self)

    public init(
        compatibility: DataCompatibilityCoordinator,
        reminderScheduler: any LoggingReminderScheduling,
        summaryScheduler: any DailySummaryScheduling,
        issueAlertScheduler: any DataIssueAlertScheduling,
        widgetRefresher: any WidgetTimelineRefreshing,
    ) {
        self.compatibility = compatibility
        self.reminderScheduler = reminderScheduler
        self.summaryScheduler = summaryScheduler
        self.issueAlertScheduler = issueAlertScheduler
        self.widgetRefresher = widgetRefresher
    }

    @discardableResult
    func publish(_ operation: @Sendable (DataCompatibilityStatus) async throws -> Void) async
        -> Result<Void, any Error>
    {
        await beginExclusive()
        defer { endExclusive() }
        do {
            let status = try await compatibility.status()
            try status.requireAccess()
            try await operation(status)
            try await compatibility.requireAccess()
            return .success(())
        } catch {
            Self.logger(attachments: [.error(error, name: "compatibility-error")]) {
                .accessBlocked(description: error.localizedDescription)
            }
            await withdrawLocked(requirement: Self.blockedRequirement(error))
            return .failure(error)
        }
    }

    func authorize(_ operation: @Sendable () async -> Bool) async -> Bool {
        do {
            try await compatibility.requireAccess()
            let authorized = await operation()
            try await compatibility.requireAccess()
            return authorized
        } catch {
            Self.logger(attachments: [.error(error, name: "compatibility-error")]) {
                .accessBlocked(description: error.localizedDescription)
            }
            await withdraw()
            return false
        }
    }

    /// Cancels owned notifications and badges without changing any saved user preference.
    public func withdraw() async {
        await beginExclusive()
        defer { endExclusive() }
        do {
            let status = try await compatibility.status()
            await withdrawLocked(requirement: status.isCompatible ? nil : status.requiredVersion)
        } catch {
            Self.logger(attachments: [.error(error, name: "compatibility-error")]) {
                .accessBlocked(description: error.localizedDescription)
            }
            await withdrawLocked(requirement: nil)
        }
    }

    private func withdrawLocked(requirement: DataCompatibilityVersion?) async {
        withdrawalRevision = WithdrawalRevision()
        do {
            try await widgetRefresher.publishCompatibility(.init(requiredVersion: requirement))
        } catch {
            Self.logger(attachments: [.error(error, name: "widget-withdrawal-error")]) {
                .accessBlocked(description: error.localizedDescription)
            }
        }
        async let reminders: Void = reminderScheduler.reconcile(
            badgeCount: 0,
            scheduleDays: [],
            reminderTime: .defaultEvening,
            enabled: false,
        )
        async let summary: Void = summaryScheduler.reconcile(
            enabled: false,
            time: .defaultMorning,
            body: "",
        )
        async let issues: Void = issueAlertScheduler.reconcile(
            enabled: false,
            time: .defaultEvening,
            body: "",
        )
        _ = await (reminders, summary, issues)
    }

    private static func blockedRequirement(_ error: any Error) -> DataCompatibilityVersion? {
        guard case let DataCompatibilityError.updateRequired(status) = error else { return nil }
        return status.requiredVersion
    }

    private func beginExclusive() async {
        if isPublishing {
            await withCheckedContinuation { waiters.append($0) }
        } else {
            isPublishing = true
        }
    }

    private func endExclusive() {
        if waiters.isEmpty { isPublishing = false } else { waiters.removeFirst().resume() }
    }
}
