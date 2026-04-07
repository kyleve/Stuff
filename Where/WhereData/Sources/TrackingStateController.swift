import Foundation
import WhereCore

public actor TrackingStateController {
    private let store: any TrackingStateStore

    public init(store: any TrackingStateStore) {
        self.store = store
    }

    public func state() async -> TrackingState {
        await store.load()
    }

    public func updateAuthorization(_ status: TrackingAuthorizationStatus) async {
        let current = await store.load()
        await store.save(
            TrackingState(
                authorizationStatus: status,
                lastWakeEventAt: current.lastWakeEventAt,
                lastRecordedSampleAt: current.lastRecordedSampleAt,
                lastWakeReason: current.lastWakeReason,
                pendingGapNotificationDates: current.pendingGapNotificationDates,
                isMonitoringActive: current.isMonitoringActive,
            ),
        )
    }

    public func markMonitoringActive(_ isActive: Bool) async {
        let current = await store.load()
        await store.save(
            TrackingState(
                authorizationStatus: current.authorizationStatus,
                lastWakeEventAt: current.lastWakeEventAt,
                lastRecordedSampleAt: current.lastRecordedSampleAt,
                lastWakeReason: current.lastWakeReason,
                pendingGapNotificationDates: current.pendingGapNotificationDates,
                isMonitoringActive: isActive,
            ),
        )
    }

    public func recordWakeEvent(_ event: TrackingWakeEvent) async {
        let current = await store.load()
        await store.save(
            TrackingState(
                authorizationStatus: current.authorizationStatus,
                lastWakeEventAt: event.timestamp,
                lastRecordedSampleAt: current.lastRecordedSampleAt,
                lastWakeReason: event.reason,
                pendingGapNotificationDates: current.pendingGapNotificationDates,
                isMonitoringActive: current.isMonitoringActive,
            ),
        )
    }

    public func recordSample(at timestamp: Date) async {
        let current = await store.load()
        await store.save(
            TrackingState(
                authorizationStatus: current.authorizationStatus,
                lastWakeEventAt: current.lastWakeEventAt,
                lastRecordedSampleAt: timestamp,
                lastWakeReason: current.lastWakeReason,
                pendingGapNotificationDates: current.pendingGapNotificationDates,
                isMonitoringActive: current.isMonitoringActive,
            ),
        )
    }

    public func scheduleGapNotification(for date: Date) async {
        let current = await store.load()
        let pending = Array(Set(current.pendingGapNotificationDates + [date])).sorted()
        await store.save(
            TrackingState(
                authorizationStatus: current.authorizationStatus,
                lastWakeEventAt: current.lastWakeEventAt,
                lastRecordedSampleAt: current.lastRecordedSampleAt,
                lastWakeReason: current.lastWakeReason,
                pendingGapNotificationDates: pending,
                isMonitoringActive: current.isMonitoringActive,
            ),
        )
    }

    public func clearGapNotifications() async {
        let current = await store.load()
        await store.save(
            TrackingState(
                authorizationStatus: current.authorizationStatus,
                lastWakeEventAt: current.lastWakeEventAt,
                lastRecordedSampleAt: current.lastRecordedSampleAt,
                lastWakeReason: current.lastWakeReason,
                pendingGapNotificationDates: [],
                isMonitoringActive: current.isMonitoringActive,
            ),
        )
    }
}
