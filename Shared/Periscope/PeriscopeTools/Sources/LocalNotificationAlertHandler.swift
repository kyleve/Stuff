import Foundation
import os
import PeriscopeCore
import UserNotifications

/// The default debug toast: posts each alerted record as a local
/// notification (requesting provisional authorization, which delivers
/// quietly without prompting). Apps with their own toast system implement
/// ``PeriscopeAlertHandler`` instead.
public struct LocalNotificationAlertHandler: PeriscopeAlertHandler {
    /// Failures posting the alert can't alert (that would loop), so they go
    /// straight to OSLog.
    private static let failureLogger = os.Logger(
        subsystem: "com.stuff.periscope",
        category: "alerts",
    )

    public init() {}

    public func handle(_ record: LogRecord) {
        let request = Self.request(for: record)
        Task {
            let center = UNUserNotificationCenter.current()
            do {
                _ = try await center.requestAuthorization(
                    options: [.alert, .sound, .provisional],
                )
                try await center.add(request)
            } catch {
                Self.failureLogger.warning(
                    "Failed to post log alert notification: \(error)",
                )
            }
        }
    }

    static func request(for record: LogRecord) -> UNNotificationRequest {
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
