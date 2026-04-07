import Foundation
import WhereCore

public actor BackgroundTrackingController {
    private enum MonitoringAction {
        case start
        case refresh
    }

    private let calendar: Calendar
    private let locationRepository: any LocationSampleRepository
    private let authorizationProvider: any LocationAuthorizationProviding
    private let wakeSource: any LocationWakeSource
    private let jurisdictionResolver: any JurisdictionResolving
    private let notificationScheduler: any TrackingNotificationScheduling
    private let trackingStateController: TrackingStateController
    private let configuration: TrackingMonitoringConfiguration
    private let now: @Sendable () -> Date

    public init(
        calendar: Calendar = .current,
        locationRepository: any LocationSampleRepository,
        authorizationProvider: any LocationAuthorizationProviding,
        wakeSource: any LocationWakeSource,
        jurisdictionResolver: any JurisdictionResolving,
        notificationScheduler: any TrackingNotificationScheduling,
        trackingStateController: TrackingStateController,
        configuration: TrackingMonitoringConfiguration = .init(),
        now: @escaping @Sendable () -> Date = Date.init,
    ) {
        self.calendar = calendar
        self.locationRepository = locationRepository
        self.authorizationProvider = authorizationProvider
        self.wakeSource = wakeSource
        self.jurisdictionResolver = jurisdictionResolver
        self.notificationScheduler = notificationScheduler
        self.trackingStateController = trackingStateController
        self.configuration = configuration
        self.now = now
    }

    public func prepareForLaunch() async {
        var authorizationStatus = await authorizationProvider.currentAuthorizationStatus()
        if authorizationStatus == .notDetermined {
            await authorizationProvider.requestAlwaysAuthorization()
            authorizationStatus = await authorizationProvider.currentAuthorizationStatus()
        }

        await applyAuthorizationStatus(authorizationStatus, action: .start)
    }

    public func requestAlwaysAuthorization() async {
        await authorizationProvider.requestAlwaysAuthorization()
        let authorizationStatus = await authorizationProvider.currentAuthorizationStatus()
        await applyAuthorizationStatus(authorizationStatus, action: .refresh)
    }

    public func refreshMonitoring() async {
        let authorizationStatus = await authorizationProvider.currentAuthorizationStatus()
        await applyAuthorizationStatus(authorizationStatus, action: .refresh)
    }

    public func handleAuthorizationStatusChange(_ status: TrackingAuthorizationStatus) async {
        await applyAuthorizationStatus(status, action: .refresh)
    }

    public func handleWakeEvent(_ event: TrackingWakeEvent) async {
        await trackingStateController.recordWakeEvent(event)

        let jurisdiction = await jurisdictionResolver.jurisdiction(for: event)
        let sample = LocationSample(
            timestamp: event.timestamp,
            jurisdiction: jurisdiction,
        )
        await locationRepository.upsert([sample])
        await trackingStateController.recordSample(at: event.timestamp)
        await refreshGapNotifications()
    }

    public func trackingState() async -> TrackingState {
        await trackingStateController.state()
    }

    private func applyAuthorizationStatus(
        _ status: TrackingAuthorizationStatus,
        action: MonitoringAction,
    ) async {
        await trackingStateController.updateAuthorization(status)

        guard status.isBackgroundAuthorized else {
            await wakeSource.stopMonitoring()
            await trackingStateController.markMonitoringActive(false)
            await clearScheduledGapNotifications()
            return
        }

        switch action {
            case .start:
                await wakeSource.startMonitoring(configuration: configuration)
            case .refresh:
                await wakeSource.refreshRegionMonitoring(configuration: configuration)
        }

        await trackingStateController.markMonitoringActive(true)
        await refreshGapNotifications()
    }

    private func refreshGapNotifications() async {
        let state = await trackingStateController.state()
        let dueDates = gapNotificationDates(for: state)
        let requests = dueDates.map(notificationRequest(for:))
        let existingIDs = state.pendingGapNotificationDates.map(notificationID(for:))

        await notificationScheduler.cancel(ids: existingIDs)
        await trackingStateController.clearGapNotifications()
        for dueDate in dueDates {
            await trackingStateController.scheduleGapNotification(for: dueDate)
        }

        for request in requests {
            await notificationScheduler.schedule(request)
        }
    }

    private func clearScheduledGapNotifications() async {
        let state = await trackingStateController.state()
        let existingIDs = state.pendingGapNotificationDates.map(notificationID(for:))
        await notificationScheduler.cancel(ids: existingIDs)
        await trackingStateController.clearGapNotifications()
    }

    private func gapNotificationDates(for state: TrackingState) -> [Date] {
        guard state.authorizationStatus.isBackgroundAuthorized else {
            return []
        }

        let referenceDate = state.lastRecordedSampleAt ?? state.lastWakeEventAt
        let startOfToday = calendar.startOfDay(for: now())

        guard let referenceDate else {
            return [notificationDate(for: startOfToday)]
        }

        let startOfReferenceDay = calendar.startOfDay(for: referenceDate)
        guard startOfReferenceDay < startOfToday else {
            return []
        }

        var dates: [Date] = []
        var cursor = startOfReferenceDay
        while cursor < startOfToday {
            if let next = calendar.date(byAdding: .day, value: 1, to: cursor) {
                dates.append(notificationDate(for: next))
                cursor = next
            } else {
                break
            }
        }
        return dates
    }

    private func notificationDate(for day: Date) -> Date {
        calendar.date(
            bySettingHour: configuration.wakeNotificationHour,
            minute: 0,
            second: 0,
            of: day,
        ) ?? day
    }

    private func notificationRequest(for date: Date) -> TrackingNotificationRequest {
        TrackingNotificationRequest(
            id: notificationID(for: date),
            title: "Tracking needs attention",
            body: "Open Where to review location coverage for missing days.",
            deliverAt: date,
        )
    }

    private func notificationID(for date: Date) -> String {
        "tracking-gap-\(Int(date.timeIntervalSince1970))"
    }
}
