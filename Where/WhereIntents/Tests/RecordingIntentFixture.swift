import Foundation
@_spi(Testing) import WhereCore

/// Admitted recording-contract services over isolated storage and the production region catalog.
@MainActor
struct RecordingIntentFixture {
    static let first = RecordingDeviceID(rawValue: UUID())
    static let second = RecordingDeviceID(rawValue: UUID())
    static let epoch = IntentTestSupport.iso("2026-06-15T12:00:00Z")

    let store: SwiftDataStore
    let access: DataCompatibilityAccess
    let services: WhereServices

    init(calendar: Calendar) async throws {
        store = try SwiftDataStore.inMemory()
        try await store.perform { [store] in try await store.raiseRequiredDataMajor(1) }
        let coordinator = DataCompatibilityCoordinator(
            store: store,
            source: .local(storeID: .init(rawValue: "recording-intent-fixture")),
            policy: .init(current: RecordingEvidencePolicy.version, supportedMajors: [0, 1]),
            activationReadiness: .pendingValidation,
        )
        access = try await coordinator.refresh()
        services = try await WhereServices.make(
            access: access,
            locationSource: IdleLocationSource(),
            installationContext: .testing,
            aggregator: DayAggregator(calendar: calendar, timeZone: calendar.timeZone),
            reminderScheduler: NoopLoggingReminderScheduler(),
            summaryScheduler: NoopDailySummaryScheduler(),
            issueAlertScheduler: NoopDataIssueAlertScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
            locationOutbox: NoOpLocationOutbox(),
            importRecoveryPersistence: NoopBackupImportRecoveryPersistence(),
            now: { Self.epoch },
        )
    }

    func addConflict() async throws {
        try await store.perform { [store] in
            for seconds in [0.0, 600, 1200] {
                for device in [Self.first, Self.second] {
                    let timestamp = Self.epoch.addingTimeInterval(seconds)
                    try await store.add(sample: LocationSample(
                        timestamp: timestamp,
                        coordinate: device == Self.first
                            ? .init(latitude: 37.33, longitude: -121.89 + seconds / 30000)
                            : .init(latitude: 40.75, longitude: -74 + seconds / 30000),
                        horizontalAccuracy: 10,
                        source: .gpsSignificantChange,
                        recordingDeviceID: device,
                        recordingDay: .resolved(.init(observedAt: timestamp, timeZone: .gmt)),
                    ))
                }
            }
        }
    }

    func selectFirst() async throws {
        let choice = try HistoryDecision(
            id: .init(rawValue: UUID()),
            author: Self.first,
            periods: [.init(start: Self.epoch, end: Self.epoch.addingTimeInterval(1201))],
            scope: .fixedPeriods,
            action: .select(Self.first),
            predecessors: [],
            version: RecordingEvidencePolicy.version,
        )
        try await store.perform { [store] in
            try await store.addVersionedHistoryRecord(RecordingControlCodec.encode(
                .source(choice),
                generationID: store.dataGeneration().id,
            ))
        }
    }
}
