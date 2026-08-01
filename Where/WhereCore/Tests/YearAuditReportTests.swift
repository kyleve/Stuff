import Foundation
import RegionKit
import Testing
@testable import WhereCore

struct YearAuditReportTests {
    private static let calendar = WhereCoreTestSupport.calendar()

    private static func makeReader() throws -> (ReportReader, SwiftDataStore) {
        let store = try SwiftDataStore.inMemory()
        let reader = ReportReader(
            store: store,
            aggregator: DayAggregator(calendar: calendar, timeZone: WhereCoreTestSupport.pacific),
            attributor: RegionAttributor.shared,
        )
        return (reader, store)
    }

    @Test func snapshotScopesEveryTableToTheYearAndOrdersTiesByUUID() async throws {
        let (reader, store) = try Self.makeReader()
        let timestamp = WhereCoreTestSupport.iso("2026-05-02T10:00:00-07:00")
        let earlierID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let laterID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let evidenceID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000003"))
        let audit = ManualEntryAudit(
            recordedAt: WhereCoreTestSupport.iso("2026-06-01T09:00:00-07:00"),
            note: "Reviewed travel records.",
            location: CapturedLocation(
                coordinate: Coordinate(latitude: 40.7128, longitude: -74.0060),
                horizontalAccuracy: 9,
                timestamp: WhereCoreTestSupport.iso("2026-06-01T08:59:58-07:00"),
            ),
        )

        try await store.perform {
            try await store.add(sample: LocationSample(
                id: laterID,
                timestamp: timestamp,
                coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
                horizontalAccuracy: 12,
                source: .gpsVisit,
            ))
            try await store.add(sample: LocationSample(
                id: earlierID,
                timestamp: timestamp,
                coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
                horizontalAccuracy: 8,
                source: .gpsSignificantChange,
            ))
            try await store.add(sample: LocationSample(
                timestamp: WhereCoreTestSupport.iso("2025-12-31T10:00:00-08:00"),
                coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
                horizontalAccuracy: 5,
                source: .gpsVisit,
            ))
            try await store.setManualDay(DayPresence(
                day: CalendarDay(year: 2026, month: 6, day: 1),
                regions: [.newYork],
                audit: audit,
            ))
            try await store.setManualDay(DayPresence(
                day: CalendarDay(year: 2025, month: 6, day: 1),
                regions: [.canada],
            ))
            try await store.write(
                evidence: Evidence(
                    id: evidenceID,
                    kind: .boardingPass,
                    capturedAt: timestamp,
                    region: .california,
                    note: "SFO arrival",
                    contentType: .pdf,
                ),
                blob: Data("excluded attachment bytes".utf8),
            )
            try await store.write(
                evidence: Evidence(
                    kind: .photo,
                    capturedAt: WhereCoreTestSupport.iso("2027-01-01T10:00:00-08:00"),
                    contentType: .image,
                ),
                blob: nil,
            )
        }

        let result = try await reader.auditReport(for: 2026)

        #expect(result.samples.map(\.sample.id) == [earlierID, laterID])
        #expect(result.manualDays.count == 1)
        #expect(result.manualDays.first?.audit == audit)
        #expect(result.evidence.map(\.id) == [evidenceID])
        #expect(result.evidence.first?.note == "SFO arrival")
        #expect(result.report.days.map(\.day) == [
            CalendarDay(year: 2026, month: 5, day: 2),
            CalendarDay(year: 2026, month: 6, day: 1),
        ])
    }

    @Test func capturedTrackedSetDrivesAttributionTotalsAndDayBases() async throws {
        let (reader, store) = try Self.makeReader()
        let evidenceID = UUID()
        let firstDay = WhereCoreTestSupport.iso("2026-03-01T12:00:00-08:00")
        try await store.perform {
            try await store.setPrimaryRegions([
                PrimaryRegion(region: .california, appearance: nil, order: 0),
            ])
            try await store.add(sample: LocationSample(
                timestamp: firstDay,
                coordinate: Coordinate(latitude: 40.7128, longitude: -74.0060),
                horizontalAccuracy: 10,
                source: .gpsVisit,
            ))
            try await store.add(sample: LocationSample(
                timestamp: firstDay.addingTimeInterval(60),
                coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
                horizontalAccuracy: 10,
                source: .manual,
            ))
            try await store.add(sample: LocationSample(
                timestamp: firstDay.addingTimeInterval(120),
                coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
                horizontalAccuracy: 10,
                source: .evidenceImplied(id: evidenceID, kind: .hotelReceipt),
            ))
            try await store.setManualDay(DayPresence(
                day: CalendarDay(year: 2026, month: 3, day: 1),
                regions: [.canada],
                isAuthoritative: false,
            ))
            try await store.setManualDay(DayPresence(
                day: CalendarDay(year: 2026, month: 3, day: 2),
                regions: [.newYork],
                isAuthoritative: true,
            ))
        }

        let result = try await reader.auditReport(for: 2026)
        let march1 = CalendarDay(year: 2026, month: 3, day: 1)
        let march2 = CalendarDay(year: 2026, month: 3, day: 2)

        #expect(result.trackedRegions == [.california])
        #expect(result.samples.first?.region == .other)
        #expect(result.report.totals == [
            .other: 1,
            .california: 1,
            .canada: 1,
            .newYork: 1,
        ])
        #expect(result.bases(on: march1, calendar: Self.calendar) == [
            .gps,
            .manualCoordinate,
            .evidenceDerivedCoordinate,
            .additiveManualEntry,
        ])
        #expect(result.bases(on: march2, calendar: Self.calendar) == [
            .authoritativeManualOverride,
        ])

        // Later settings changes cannot retroactively alter the returned value.
        try await store.perform {
            try await store.setPrimaryRegions([
                PrimaryRegion(region: .newYork, appearance: nil, order: 0),
            ])
        }
        #expect(result.trackedRegions == [.california])
        #expect(result.samples.first?.region == .other)
    }

    @Test func emptyYearStillCarriesPolicyTimezoneAndProvenance() async throws {
        let (reader, _) = try Self.makeReader()

        let result = try await reader.auditReport(for: 2026)

        #expect(result.report.year == 2026)
        #expect(result.report.days.isEmpty)
        #expect(result.samples.isEmpty)
        #expect(result.manualDays.isEmpty)
        #expect(result.evidence.isEmpty)
        #expect(Set(result.trackedRegions) == SwiftDataStore.defaultTrackedRegions)
        #expect(result.timeZone == WhereCoreTestSupport.pacific)
        #expect(!result.regionDataSources.isEmpty)
    }
}
