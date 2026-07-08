import Foundation
import os
import PeriscopeCore
import UserNotifications

/// The default debug toast: posts each alerted record as a local
/// notification (requesting provisional authorization, which delivers
/// quietly without prompting). The authorization outcome is asked for once
/// and cached — an error storm must not do a daemon round-trip per record.
/// Apps with their own toast system implement ``PeriscopeAlertHandler``
/// instead.
public struct LocalNotificationAlertHandler: PeriscopeAlertHandler {
    /// The cached authorization outcome. `unknown` retries on the next
    /// alert (a failed request may be transient); `denied` goes quiet
    /// without re-asking.
    private enum Authorization {
        case unknown
        case granted
        case denied
    }

    /// Failures posting the alert can't alert (that would loop), so they go
    /// straight to OSLog.
    private nonisolated static let failureLogger = os.Logger(
        subsystem: "com.stuff.periscope",
        category: "alerts",
    )

    private let center: any AlertNotificationCenter
    private let authorization = OSAllocatedUnfairLock(initialState: Authorization.unknown)

    public init() {
        self.init(center: UNUserNotificationCenterAlertAdapter(center: .current()))
    }

    init(center: any AlertNotificationCenter) {
        self.center = center
    }

    public func handle(_ record: LogRecord) {
        Task {
            await post(for: record)
        }
    }

    /// The posting path, factored from `handle` so tests can await it
    /// deterministically. Explicitly nonisolated (the handler protocol is
    /// `@MainActor`, which would otherwise infer isolation here) so the
    /// non-Sendable `UNNotificationRequest` is built in a disconnected
    /// region and can be sent to the center.
    nonisolated func post(for record: LogRecord) async {
        do {
            switch authorization.withLock({ $0 }) {
                case .granted:
                    break
                case .denied:
                    return
                case .unknown:
                    let granted = try await center.requestAuthorization(
                        options: [.alert, .sound, .provisional],
                    )
                    authorization.withLock { $0 = granted ? .granted : .denied }
                    guard granted else {
                        Self.failureLogger.warning(
                            "Log alert notifications not authorized; alerts stay quiet",
                        )
                        return
                    }
            }
            try await center.add(Self.request(for: record))
        } catch {
            Self.failureLogger.warning(
                "Failed to post log alert notification: \(error)",
            )
        }
    }

    nonisolated static func request(for record: LogRecord) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "\(record.level.name.capitalized): \(record.eventName)"
        content.body = record.message
        return UNNotificationRequest(
            identifier: "periscope-alert-\(record.id.uuidString)",
            content: content,
            trigger: nil,
        )
    }
}

/// The slice of `UNUserNotificationCenter` the alert handler needs — a seam
/// so tests can drive authorization outcomes and capture posts (the same
/// shape as Where's `NotificationReminderCenter`).
protocol AlertNotificationCenter: Sendable {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: sending UNNotificationRequest) async throws
}

/// Production bridge. `@unchecked Sendable` is justified the same way as
/// Where's adapter: `UNUserNotificationCenter` is documented thread-safe.
final class UNUserNotificationCenterAlertAdapter: AlertNotificationCenter,
    @unchecked Sendable
{
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter) {
        self.center = center
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await center.requestAuthorization(options: options)
    }

    func add(_ request: sending UNNotificationRequest) async throws {
        try await center.add(request)
    }
}
