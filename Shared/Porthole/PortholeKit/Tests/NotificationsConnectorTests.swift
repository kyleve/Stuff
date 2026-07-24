#if canImport(UserNotifications)
    import Foundation
    import PortholeCore
    @_spi(Testing) import PortholeKit
    import Testing

    private final class FakeNotificationCenter: NotificationCenterProviding, @unchecked Sendable {
        var settings = NotificationSettingsSnapshot(
            authorizationStatus: "authorized",
            alertSetting: "enabled",
            badgeSetting: "enabled",
            soundSetting: "disabled",
            lockScreenSetting: "enabled",
        )
        var pending: [PendingNotificationInfo] = []
        var delivered: [DeliveredNotificationInfo] = []
        private(set) var removed: [String] = []

        func settingsSnapshot() async -> NotificationSettingsSnapshot {
            settings
        }

        func pendingRequests() async -> [PendingNotificationInfo] {
            pending
        }

        func deliveredNotifications() async -> [DeliveredNotificationInfo] {
            delivered
        }

        func removePending(identifiers: [String]) async {
            removed.append(contentsOf: identifiers)
        }
    }

    struct NotificationsConnectorTests {
        private func source(
            _ connector: NotificationsConnector,
            _ id: PortholeDataSourceID,
        ) -> PortholeDataSource {
            connector.dataSources().first { $0.descriptor.id == id }!
        }

        @Test func settingsRowMapsSnapshot() async throws {
            let center = FakeNotificationCenter()
            let connector = NotificationsConnector(center: center)
            let page = try await source(connector, "settings").fetch(PortholeQuery())
            #expect(page.rows.count == 1)
            #expect(page.rows.first?["authorizationStatus"]?.stringValue == "authorized")
            #expect(page.rows.first?["soundSetting"]?.stringValue == "disabled")
        }

        @Test func pendingRowsIncludeTriggerAndFireDate() async throws {
            let center = FakeNotificationCenter()
            let fireDate = Date(timeIntervalSince1970: 1_700_000_000)
            center.pending = [
                PendingNotificationInfo(
                    identifier: "a",
                    title: "T",
                    body: "B",
                    triggerDescription: "UNCalendarNotificationTrigger",
                    nextFireDate: fireDate,
                ),
            ]
            let connector = NotificationsConnector(center: center)
            let page = try await source(connector, "pending").fetch(PortholeQuery())
            #expect(page.rows.first?["identifier"]?.stringValue == "a")
            #expect(page.rows.first?["trigger"]?.stringValue == "UNCalendarNotificationTrigger")
            #expect(page.rows.first?["nextFireDate"]?.dateValue != nil)
        }

        @Test func deliveredRowsMap() async throws {
            let center = FakeNotificationCenter()
            center.delivered = [DeliveredNotificationInfo(
                identifier: "d",
                title: "T",
                body: "B",
                date: Date(),
            )]
            let connector = NotificationsConnector(center: center)
            let page = try await source(connector, "delivered").fetch(PortholeQuery())
            #expect(page.rows.first?["identifier"]?.stringValue == "d")
        }

        @Test func removePendingCallsThroughAndCounts() async throws {
            let center = FakeNotificationCenter()
            let connector = NotificationsConnector(center: center)
            let action = try #require(connector.actions()
                .first { $0.descriptor.id == "remove-pending" })
            #expect(action.descriptor.isDestructive)
            let result = try await action.handler(.object(["identifiers": .array(["x", "y"])]))
            #expect(result["removed"]?.intValue == 2)
            #expect(center.removed == ["x", "y"])
        }
    }
#endif
