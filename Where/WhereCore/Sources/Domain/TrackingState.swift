import Foundation

public struct TrackingState: Codable, Equatable, Sendable {
    public let authorizationStatus: TrackingAuthorizationStatus
    public let lastWakeEventAt: Date?
    public let lastRecordedSampleAt: Date?
    public let lastWakeReason: TrackingWakeReason?
    public let pendingGapNotificationDates: [Date]
    public let isMonitoringActive: Bool

    public init(
        authorizationStatus: TrackingAuthorizationStatus,
        lastWakeEventAt: Date? = nil,
        lastRecordedSampleAt: Date? = nil,
        lastWakeReason: TrackingWakeReason? = nil,
        pendingGapNotificationDates: [Date] = [],
        isMonitoringActive: Bool = false,
    ) {
        self.authorizationStatus = authorizationStatus
        self.lastWakeEventAt = lastWakeEventAt
        self.lastRecordedSampleAt = lastRecordedSampleAt
        self.lastWakeReason = lastWakeReason
        self.pendingGapNotificationDates = pendingGapNotificationDates
        self.isMonitoringActive = isMonitoringActive
    }

    public func runtimeStatus(
        at referenceDate: Date,
        staleInterval: TimeInterval = 36 * 60 * 60,
    ) -> TrackingStatus {
        guard authorizationStatus.isBackgroundAuthorized else {
            return .needsAttention
        }

        guard isMonitoringActive else {
            return .needsAttention
        }

        guard let lastRecordedSampleAt else {
            return .needsAttention
        }

        if referenceDate.timeIntervalSince(lastRecordedSampleAt) > staleInterval {
            return .needsAttention
        }

        if let lastWakeEventAt, lastWakeEventAt > lastRecordedSampleAt {
            return .needsReview
        }

        return .healthy
    }
}
