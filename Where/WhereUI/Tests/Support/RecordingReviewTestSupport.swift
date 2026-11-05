import Foundation
import RegionKit
import Testing
@_spi(Testing) import WhereCore
@testable import WhereUI

/// Exercises review presentation over the real admitted store, source-choice transaction,
/// historical scanner, and compatibility lifetime. No platform accounts or sensors are used.
@MainActor
enum RecordingReviewTestSupport {
    nonisolated static let first =
        RecordingDeviceID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
    nonisolated static let second =
        RecordingDeviceID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)
    nonisolated static let policy = DataCompatibilityPolicy(
        current: .init(major: 1, minor: 0, patch: 0),
        supportedMajors: [1],
    )
    nonisolated static let day = CalendarDay(year: 2026, month: 1, day: 1)

    struct Fixture {
        let store: SwiftDataStore
        let compatibility: DataCompatibilityCoordinator
        let services: WhereServices
        let periods: [RecordingPeriod]

        func references() async throws -> [RecordingReviewReference] {
            let scan = try await services.resolution.historicalScan(
                driftThresholdMeters: 1000,
                force: true,
            )
            return try scan.recording.issues.flatMap { try Array(scan.references(for: $0)) }
        }

        func controls() async throws -> RecordingControlSnapshot {
            try await RecordingControlStore(store: store, policy: policy).snapshot()
        }

        func add(_ samples: [LocationSample]) async throws {
            try await store.perform {
                for sample in samples {
                    try await store.add(sample: sample)
                }
            }
        }
    }

    nonisolated static func date(_ seconds: Double) -> Date {
        // 2026-01-01 00:00 UTC, with real instants independent of the fixture's viewing zone.
        Date(timeIntervalSince1970: 1_767_225_600 + seconds)
    }

    nonisolated static func sample(
        deviceID: RecordingDeviceID,
        seconds: Double,
        unresolved: Bool = false,
    ) throws -> LocationSample {
        let timestamp = date(seconds)
        return try LocationSample(
            id: UUID(),
            timestamp: timestamp,
            coordinate: deviceID == first
                ? Coordinate(latitude: 37.78, longitude: -122.42 + seconds / 100_000)
                : Coordinate(latitude: 40.71, longitude: -74.0 + seconds / 100_000),
            horizontalAccuracy: 10,
            source: .gpsSignificantChange,
            recordingDeviceID: deviceID,
            recordingDay: unresolved ? .unresolved : .resolved(.init(
                observedAt: timestamp,
                timeZone: .gmt,
            )),
        )
    }

    static func strongMovementSamples() throws -> [LocationSample] {
        try (0 ... 2).flatMap { index in
            try [first, second]
                .map { device in
                    let timestamp = date(Double(index) * 600)
                    return try LocationSample(
                        id: UUID(),
                        timestamp: timestamp,
                        coordinate: device == first
                            ? Coordinate(latitude: 37.78, longitude: -122.42 + Double(index) * 0.02)
                            : Coordinate(latitude: 40.71, longitude: -74),
                        horizontalAccuracy: 10,
                        source: .gpsSignificantChange,
                        recordingDeviceID: device,
                        recordingDay: .resolved(.init(observedAt: timestamp, timeZone: .gmt)),
                    )
                }
        }
    }

    static func fixture(unresolved: Bool = false) async throws -> Fixture {
        let samples = try [0.0, 600, 1200].flatMap { seconds in
            try [first, second].map { try sample(
                deviceID: $0,
                seconds: seconds,
                unresolved: unresolved,
            ) }
        }
        return try await fixture(samples: samples)
    }

    static func fixture(samples: [LocationSample]) async throws -> Fixture {
        let store = try SwiftDataStore.inMemory()
        try await store.perform {
            try await store.raiseRequiredDataMajor(1)
            for deviceID in [first, second] {
                try await store.addRecordingDeviceProfile(.init(
                    id: deviceID,
                    systemName: deviceID == first ? "Phone One" : "Phone Two",
                    kind: .phone,
                    registeredAt: date(0),
                    registrationGenerationID: .initial,
                ))
            }
            for sample in samples {
                try await store.add(sample: sample)
            }
        }
        let compatibility = DataCompatibilityCoordinator(
            store: store,
            source: .local(storeID: .init(rawValue: "recording-review-fixture")),
            policy: policy,
            activationReadiness: .pendingValidation,
        )
        let access = try await compatibility.refresh()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let services = try await WhereServices.make(
            access: access,
            locationSource: ScriptedLocationSource(authorizationStatus: .always),
            installationContext: .testing,
            aggregator: DayAggregator(calendar: calendar, timeZone: .gmt),
            reminderScheduler: NoopEveningReminderScheduler(),
            summaryScheduler: NoopDailySummaryScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
            locationOutbox: NoOpLocationOutbox(),
            importRecoveryPersistence: NoopBackupImportRecoveryPersistence(),
            now: { date(24 * 60 * 60) },
        )
        return try Fixture(
            store: store,
            compatibility: compatibility,
            services: services,
            periods: [.init(start: date(0), end: date(1201))],
        )
    }

    static func preview(_ model: RecordingChoiceModel) throws -> RecordingChoiceInspection.Preview {
        guard case let .ready(preview) = model.inspection else {
            throw TestFailure.expectedPreview
        }
        return preview
    }

    enum TestFailure: Error { case expectedPreview, interruptedSaveReceipt }
}
