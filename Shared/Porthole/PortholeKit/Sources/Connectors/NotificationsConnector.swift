#if canImport(UserNotifications)
    import Foundation
    import PortholeCore
    import UserNotifications

    /// A settings snapshot, minus the framework types, so it's `Sendable` and
    /// scriptable in tests.
    public struct NotificationSettingsSnapshot: Sendable, Equatable {
        public var authorizationStatus: String
        public var alertSetting: String
        public var badgeSetting: String
        public var soundSetting: String
        public var lockScreenSetting: String

        public init(
            authorizationStatus: String,
            alertSetting: String,
            badgeSetting: String,
            soundSetting: String,
            lockScreenSetting: String,
        ) {
            self.authorizationStatus = authorizationStatus
            self.alertSetting = alertSetting
            self.badgeSetting = badgeSetting
            self.soundSetting = soundSetting
            self.lockScreenSetting = lockScreenSetting
        }
    }

    public struct PendingNotificationInfo: Sendable, Equatable {
        public var identifier: String
        public var title: String
        public var body: String
        public var triggerDescription: String
        public var nextFireDate: Date?

        public init(
            identifier: String,
            title: String,
            body: String,
            triggerDescription: String,
            nextFireDate: Date?,
        ) {
            self.identifier = identifier
            self.title = title
            self.body = body
            self.triggerDescription = triggerDescription
            self.nextFireDate = nextFireDate
        }
    }

    public struct DeliveredNotificationInfo: Sendable, Equatable {
        public var identifier: String
        public var title: String
        public var body: String
        public var date: Date

        public init(identifier: String, title: String, body: String, date: Date) {
            self.identifier = identifier
            self.title = title
            self.body = body
            self.date = date
        }
    }

    /// The notification-center surface the connector needs, so tests inject a
    /// fake instead of the real `UNUserNotificationCenter`.
    public protocol NotificationCenterProviding: Sendable {
        func settingsSnapshot() async -> NotificationSettingsSnapshot
        func pendingRequests() async -> [PendingNotificationInfo]
        func deliveredNotifications() async -> [DeliveredNotificationInfo]
        func removePending(identifiers: [String]) async
    }

    /// The built-in `notifications` connector: authorization/settings, pending and
    /// delivered notifications, and a remove-pending action. Auto-registered by
    /// ``Porthole``.
    public final class NotificationsConnector: PortholeConnector {
        public let descriptor = PortholeConnectorDescriptor(
            id: "notifications",
            title: "Notifications",
            summary: "Notification authorization and settings, pending and delivered notifications, and removing pending ones.",
            version: 1,
        )

        private let center: NotificationCenterProviding

        public init() {
            center = SystemNotificationCenter()
        }

        @_spi(Testing)
        public init(center: NotificationCenterProviding) {
            self.center = center
        }

        public func actions() -> [PortholeAction] {
            let center = center
            return [
                PortholeAction(
                    descriptor: PortholeActionDescriptor(
                        id: "remove-pending",
                        title: "Remove pending",
                        summary: "Cancel pending notification requests by identifier.",
                        parameters: .object(
                            ["identifiers": .array(of: .string())],
                            required: ["identifiers"],
                        ),
                        isDestructive: true,
                    ),
                    handler: { parameters in
                        let identifiers = (parameters["identifiers"]?.arrayValue ?? [])
                            .compactMap(\.stringValue)
                        await center.removePending(identifiers: identifiers)
                        return .object(["removed": .int(Int64(identifiers.count))])
                    },
                ),
            ]
        }

        public func dataSources() -> [PortholeDataSource] {
            let center = center
            return [
                PortholeDataSource(
                    descriptor: PortholeDataSourceDescriptor(
                        id: "settings",
                        title: "Settings",
                        summary: "A single row with authorization status and per-kind settings.",
                        rowSchema: .object([
                            "authorizationStatus": .string(),
                            "alertSetting": .string(),
                            "badgeSetting": .string(),
                            "soundSetting": .string(),
                            "lockScreenSetting": .string(),
                        ]),
                        filters: .object([:]),
                        supportsSubscription: false,
                    ),
                    fetch: { _ in
                        let snapshot = await center.settingsSnapshot()
                        return PortholePage(rows: [.object([
                            "authorizationStatus": .string(snapshot.authorizationStatus),
                            "alertSetting": .string(snapshot.alertSetting),
                            "badgeSetting": .string(snapshot.badgeSetting),
                            "soundSetting": .string(snapshot.soundSetting),
                            "lockScreenSetting": .string(snapshot.lockScreenSetting),
                        ])], totalCount: 1)
                    },
                ),
                PortholeDataSource(
                    descriptor: PortholeDataSourceDescriptor(
                        id: "pending",
                        title: "Pending",
                        summary: "Scheduled notification requests not yet delivered.",
                        rowSchema: .object([
                            "identifier": .string(),
                            "title": .string(),
                            "body": .string(),
                            "trigger": .string(),
                            "nextFireDate": .date(),
                        ]),
                        filters: .object([:]),
                        supportsSubscription: false,
                    ),
                    fetch: { _ in
                        let rows = await center.pendingRequests().map { request -> PortholeValue in
                            var object: [String: PortholeValue] = [
                                "identifier": .string(request.identifier),
                                "title": .string(request.title),
                                "body": .string(request.body),
                                "trigger": .string(request.triggerDescription),
                            ]
                            if let fireDate = request
                                .nextFireDate { object["nextFireDate"] = .date(fireDate) }
                            return .object(object)
                        }
                        return PortholePage(rows: rows, totalCount: rows.count)
                    },
                ),
                PortholeDataSource(
                    descriptor: PortholeDataSourceDescriptor(
                        id: "delivered",
                        title: "Delivered",
                        summary: "Notifications currently in Notification Center.",
                        rowSchema: .object([
                            "identifier": .string(),
                            "title": .string(),
                            "body": .string(),
                            "date": .date(),
                        ]),
                        filters: .object([:]),
                        supportsSubscription: false,
                    ),
                    fetch: { _ in
                        let rows = await center.deliveredNotifications()
                            .map { notification -> PortholeValue in
                                .object([
                                    "identifier": .string(notification.identifier),
                                    "title": .string(notification.title),
                                    "body": .string(notification.body),
                                    "date": .date(notification.date),
                                ])
                            }
                        return PortholePage(rows: rows, totalCount: rows.count)
                    },
                ),
            ]
        }
    }

    /// The production ``NotificationCenterProviding`` over `UNUserNotificationCenter`.
    struct SystemNotificationCenter: NotificationCenterProviding {
        private var center: UNUserNotificationCenter {
            .current()
        }

        func settingsSnapshot() async -> NotificationSettingsSnapshot {
            let settings = await center.notificationSettings()
            return NotificationSettingsSnapshot(
                authorizationStatus: Self.string(settings.authorizationStatus),
                alertSetting: Self.string(settings.alertSetting),
                badgeSetting: Self.string(settings.badgeSetting),
                soundSetting: Self.string(settings.soundSetting),
                lockScreenSetting: Self.string(settings.lockScreenSetting),
            )
        }

        func pendingRequests() async -> [PendingNotificationInfo] {
            await center.pendingNotificationRequests().map { request in
                PendingNotificationInfo(
                    identifier: request.identifier,
                    title: request.content.title,
                    body: request.content.body,
                    triggerDescription: request.trigger
                        .map { String(describing: type(of: $0)) } ?? "none",
                    nextFireDate: Self.nextFireDate(for: request.trigger),
                )
            }
        }

        func deliveredNotifications() async -> [DeliveredNotificationInfo] {
            await center.deliveredNotifications().map { notification in
                DeliveredNotificationInfo(
                    identifier: notification.request.identifier,
                    title: notification.request.content.title,
                    body: notification.request.content.body,
                    date: notification.date,
                )
            }
        }

        func removePending(identifiers: [String]) async {
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }

        private static func nextFireDate(for trigger: UNNotificationTrigger?) -> Date? {
            switch trigger {
                case let calendar as UNCalendarNotificationTrigger:
                    calendar.nextTriggerDate()
                case let interval as UNTimeIntervalNotificationTrigger:
                    interval.nextTriggerDate()
                default:
                    nil
            }
        }

        private static func string(_ status: UNAuthorizationStatus) -> String {
            switch status {
                case .notDetermined: "notDetermined"
                case .denied: "denied"
                case .authorized: "authorized"
                case .provisional: "provisional"
                case .ephemeral: "ephemeral"
                @unknown default: "unknown"
            }
        }

        private static func string(_ setting: UNNotificationSetting) -> String {
            switch setting {
                case .notSupported: "notSupported"
                case .disabled: "disabled"
                case .enabled: "enabled"
                @unknown default: "unknown"
            }
        }
    }
#endif
