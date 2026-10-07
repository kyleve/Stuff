import Foundation
@_spi(Testing) @testable import WhereCore

enum CompatibilityOutputTestSupport {
    struct Gate {
        struct Channel {
            let stream: AsyncStream<Void>
            let continuation: AsyncStream<Void>.Continuation

            init() {
                (stream, continuation) = AsyncStream<Void>
                    .makeStream(bufferingPolicy: .bufferingNewest(1))
            }
        }

        let entered = Channel()
        let release = Channel()

        func suspend() async {
            entered.continuation.yield()
            for await _ in release.stream {
                break
            }
        }

        func waitUntilEntered() async {
            for await _ in entered.stream {
                break
            }
        }

        func resume() {
            release.continuation.yield(); release.continuation.finish()
        }
    }

    actor Scheduler: LoggingReminderScheduling, DailySummaryScheduling, DataIssueAlertScheduling {
        private(set) var enabled = false
        private(set) var badgeCount = 0
        private(set) var requests = 0
        private var nextPublicationGate: Gate?

        func holdNextPublication(_ gate: Gate) {
            nextPublicationGate = gate
        }

        func requestAuthorization() -> Bool {
            requests += 1; return true
        }

        func isAuthorized() -> Bool {
            true
        }

        func reconcile(
            badgeCount: Int,
            scheduleDays _: [Date],
            reminderTime _: ReminderTime,
            enabled: Bool,
        ) {
            self.badgeCount = badgeCount
            self.enabled = enabled
        }

        func reconcile(enabled: Bool, time _: ReminderTime, body _: String) async {
            if enabled, let gate = nextPublicationGate {
                nextPublicationGate = nil
                await gate.suspend()
            }
            self.enabled = enabled
        }
    }

    actor Widgets: WidgetTimelineRefreshing {
        private var publicationFails = false
        private var nextPublicationError: (any Error)?
        private var nextCompatibilityError: (any Error)?
        private var nextPublicationGate: Gate?

        func holdNextPublication(_ gate: Gate) {
            nextPublicationGate = gate
        }

        func failPublication() {
            publicationFails = true
        }

        func failNextPublication(with error: any Error) {
            nextPublicationError = error
        }

        func failNextCompatibilityPublication(with error: any Error) {
            nextCompatibilityError = error
        }

        private(set) var snapshots: [WidgetSnapshot] = []
        private(set) var compatibility: [WidgetCompatibilitySnapshot] = []
        func publish(_ snapshot: WidgetSnapshot) async throws {
            struct PublicationFailure: Error {}
            if publicationFails { throw PublicationFailure() }
            if let error = nextPublicationError {
                nextPublicationError = nil
                throw error
            }
            if let gate = nextPublicationGate {
                nextPublicationGate = nil
                await gate.suspend()
            }
            snapshots.append(snapshot)
        }

        func publishCompatibility(_ snapshot: WidgetCompatibilitySnapshot) throws {
            if let error = nextCompatibilityError {
                nextCompatibilityError = nil
                throw error
            }
            compatibility.append(snapshot)
        }
    }

    struct World {
        let store: SwiftDataStore
        let services: DataCompatibilityServices
        let reminders: Scheduler
        let summary: Scheduler
        let issues: Scheduler
        let widgets: Widgets
    }

    static func makeWorld() throws -> World {
        try makeWorld(store: SwiftDataStore.inMemory())
    }

    static func makeWorld(store: SwiftDataStore) -> World {
        let reminders = Scheduler()
        let summary = Scheduler()
        let issues = Scheduler()
        let widgets = Widgets()
        let services = DataCompatibilityServices(
            store: store,
            currentDeviceID: CurrentRecordingDevice.preview.id,
            reminderScheduler: reminders,
            summaryScheduler: summary,
            issueAlertScheduler: issues,
            widgetRefresher: widgets,
        )
        return World(
            store: store,
            services: services,
            reminders: reminders,
            summary: summary,
            issues: issues,
            widgets: widgets,
        )
    }

    static func makeOutputs(
        store: any WhereStore,
        widgetRefresher: any WidgetTimelineRefreshing,
    ) -> DataCompatibilityOutputs {
        DataCompatibilityServices(
            store: store,
            currentDeviceID: CurrentRecordingDevice.preview.id,
            reminderScheduler: NoopLoggingReminderScheduler(),
            summaryScheduler: NoopDailySummaryScheduler(),
            issueAlertScheduler: NoopDataIssueAlertScheduler(),
            widgetRefresher: widgetRefresher,
        ).outputs
    }

    static func makeIncompatible(_ store: SwiftDataStore) async throws {
        let version = CompatibilityTestSupport.nextVersion
        await store.setSupportedDataCompatibilityVersionForTesting(version)
        try await store.perform { try await store.requireDataCompatibility(version) }
        await store.setSupportedDataCompatibilityVersionForTesting(.initial)
    }
}
