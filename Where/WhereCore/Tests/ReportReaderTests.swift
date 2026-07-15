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

    @Test func yearIntervalCoversTheRequestedYear() throws {
        let (reader, _) = try Self.makeReader()
        let interval = reader.yearInterval(year: 2026)
        #expect(WhereCoreTestSupport.calendar().component(.year, from: interval.start) == 2026)
    }
}
