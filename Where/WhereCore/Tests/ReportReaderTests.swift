import Foundation
import RegionKit
import Testing
@testable import WhereCore

/// Covers the standalone read path the controller (and, later, the reminder /
/// daily-summary reconcilers) delegate every report read to.
struct ReportReaderTests {
    private static func makeReader() throws -> (ReportReader, SwiftDataStore) {
        let store = try SwiftDataStore.inMemory()
        let aggregator = DayAggregator(
            calendar: WhereCoreTestSupport.calendar(),
            timeZone: WhereCoreTestSupport.pacific,
        )
        let reader = ReportReader(
            store: store,
            aggregator: aggregator,
            attributor: RegionAttributor.shared,
        )
        return (reader, store)
    }

    @Test func yearReportAggregatesSamplesAndManualDays() async throws {
        let (reader, store) = try Self.makeReader()
        try await store.perform {
            try await store.add(sample: LocationSample(
                timestamp: WhereCoreTestSupport.iso("2026-01-10T12:00:00-08:00"),
                coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
                horizontalAccuracy: 0,
                source: .gpsSignificantChange,
            ))
            try await store.setManualDay(DayPresence(
                date: WhereCoreTestSupport.iso("2026-02-01T00:00:00-08:00"),
                in: WhereCoreTestSupport.calendar(),
                regions: [.newYork],
            ))
        }

        let report = try await reader.yearReport(for: 2026)
        #expect(report.days.count == 2)
        #expect(report.totals == [.california: 1, .newYork: 1])
    }

    @Test func yearReportAppliesDeviceRecordingCutoffs() async throws {
        let (reader, store) = try Self.makeReader()
        let deviceID = try RecordingDeviceID(
            rawValue: #require(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")),
        )
        try await store.perform {
            try await store.addRecordingPolicyChange(RecordingPolicyChange(
                id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
                deviceID: deviceID,
                parentIDs: [],
                revision: 0,
                issuedAt: WhereCoreTestSupport.iso("2026-01-01T00:00:00-08:00"),
                issuedByDeviceID: deviceID,
                effectiveAt: WhereCoreTestSupport.iso("2026-01-01T00:00:00-08:00"),
                state: .on,
                reason: .initialRegistration,
            ))
            try await store.add(sample: LocationSample(
                timestamp: WhereCoreTestSupport.iso("2026-01-10T12:00:00-08:00"),
                coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
                horizontalAccuracy: 0,
                source: .gpsVisit,
                recordingDeviceID: deviceID,
            ))
            try await store.add(sample: LocationSample(
                timestamp: WhereCoreTestSupport.iso("2026-01-12T12:00:00-08:00"),
                coordinate: Coordinate(latitude: 40.7128, longitude: -74.0060),
                horizontalAccuracy: 0,
                source: .gpsVisit,
                recordingDeviceID: deviceID,
            ))
            try await store.addRecordingPolicyChange(RecordingPolicyChange(
                id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
                deviceID: deviceID,
                parentIDs: [UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!],
                revision: 1,
                issuedAt: WhereCoreTestSupport.iso("2026-01-11T00:00:00-08:00"),
                issuedByDeviceID: deviceID,
                effectiveAt: WhereCoreTestSupport.iso("2026-01-11T00:00:00-08:00"),
                state: .off,
                reason: .userCommand,
            ))
        }

        let report = try await reader.yearReport(for: 2026)

        #expect(report.days.count == 1)
        #expect(report.totals == [.california: 1])
    }

    @Test func manualDaysReturnsOnlyTheRequestedYear() async throws {
        let (reader, store) = try Self.makeReader()
        try await store.perform {
            try await store.setManualDay(DayPresence(
                date: WhereCoreTestSupport.iso("2026-02-01T00:00:00-08:00"),
                in: WhereCoreTestSupport.calendar(),
                regions: [.newYork],
            ))
            // A day just before the requested year (Pacific) must be excluded.
            try await store.setManualDay(DayPresence(
                date: WhereCoreTestSupport.iso("2025-12-31T00:00:00-08:00"),
                in: WhereCoreTestSupport.calendar(),
                regions: [.california],
            ))
        }

        let days = try await reader.manualDays(inYear: 2026)
        #expect(days.count == 1)
        #expect(days.first?.regions == [.newYork])
    }

    @Test func locationsAndRepresentativeCoordinatesReadFromSamples() async throws {
        let (reader, store) = try Self.makeReader()
        let sf = Coordinate(latitude: 37.7749, longitude: -122.4194)
        try await store.perform {
            try await store.add(sample: LocationSample(
                timestamp: WhereCoreTestSupport.iso("2026-03-15T12:00:00-07:00"),
                coordinate: sf,
                horizontalAccuracy: 0,
                source: .gpsSignificantChange,
            ))
        }

        let locations = try await reader.locations(in: .california, year: 2026)
        #expect(!locations.isEmpty)

        let representative = try await reader.representativeCoordinates(for: 2026)
        #expect(representative[.california] != nil)
    }

    /// The scan's one-read bundle: `report`, `.other` day coordinates, and the
    /// GPS `daySamples` all come from a single year-samples read and stay
    /// consistent — and the GPS-only `daySamples` drops a manual coordinate.
    @Test func dataIssueReadsBuildsAllProjectionsFromOneRead() async throws {
        let (reader, store) = try Self.makeReader()
        let sf = Coordinate(latitude: 37.7749, longitude: -122.4194) // California
        let midOcean = Coordinate(latitude: 0, longitude: -160) // .other
        try await store.perform {
            try await store.add(sample: LocationSample(
                timestamp: WhereCoreTestSupport.iso("2026-03-15T12:00:00-07:00"),
                coordinate: sf,
                horizontalAccuracy: 0,
                source: .gpsSignificantChange,
            ))
            try await store.add(sample: LocationSample(
                timestamp: WhereCoreTestSupport.iso("2026-03-16T12:00:00-07:00"),
                coordinate: midOcean,
                horizontalAccuracy: 0,
                source: .gpsSignificantChange,
            ))
            // A manual coordinate must not feed the speed-based day samples.
            try await store.add(sample: LocationSample(
                timestamp: WhereCoreTestSupport.iso("2026-03-15T18:00:00-07:00"),
                coordinate: sf,
                horizontalAccuracy: 0,
                source: .manual,
            ))
        }

        let reads = try await reader.dataIssueReads(for: 2026)

        #expect(reads.report.totals[.california] == 1)
        #expect(reads.report.totals[.other] == 1)

        let march16 = CalendarDay(year: 2026, month: 3, day: 16)
        #expect(reads.otherDayCoordinates[march16]?.isEmpty == false)

        // March 15 had a GPS fix and a manual one; only the GPS fix is kept.
        let march15 = CalendarDay(year: 2026, month: 3, day: 15)
        let day15 = reads.daySamples.samples(on: march15)
        #expect(day15.count == 1)
        #expect(day15.first?.source == .gpsSignificantChange)
    }

    @Test func yearIntervalCoversTheRequestedYear() throws {
        let (reader, _) = try Self.makeReader()
        let interval = reader.yearInterval(year: 2026)
        #expect(WhereCoreTestSupport.calendar().component(.year, from: interval.start) == 2026)
    }
}
