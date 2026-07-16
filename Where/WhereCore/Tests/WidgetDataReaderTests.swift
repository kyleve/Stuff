import Foundation
import RegionKit
import Testing
import WhereCore

struct WidgetDataReaderTests {
    private static func makeReader() throws -> (WidgetDataReader, SwiftDataStore) {
        let store = try SwiftDataStore.inMemory()
        let reader = WidgetDataReader(
            store: store,
            aggregator: DayAggregator(
                calendar: WhereCoreTestSupport.calendar(),
                timeZone: WhereCoreTestSupport.pacific,
            ),
        )
        return (reader, store)
    }

    private static func sample(at isoString: String, latitude: Double, longitude: Double)
        -> LocationSample
    {
        LocationSample(
            timestamp: WhereCoreTestSupport.iso(isoString),
            coordinate: Coordinate(latitude: latitude, longitude: longitude),
            horizontalAccuracy: 5,
            source: .manual,
        )
    }

    @Test func emptyStoreYieldsEmptySnapshot() async throws {
        let (reader, _) = try Self.makeReader()

        let snapshot = try await reader
            .snapshot(asOf: WhereCoreTestSupport.iso("2026-03-15T12:00:00-07:00"))

        #expect(snapshot.year == 2026)
        #expect(snapshot.dayRegions.isEmpty)
        #expect(snapshot.totals.isEmpty)
        #expect(snapshot.appearances.isEmpty)
    }

    @Test func snapshotCarriesPickedRegionAppearances() async throws {
        let (reader, store) = try Self.makeReader()
        let caLook = RegionAppearance(color: .orange, emoji: "🌴", symbolName: "sun.max.fill")
        try await store.perform {
            try await store.setPrimaryRegions([
                PrimaryRegion(region: .california, appearance: caLook, order: 0),
                // A tracked region with no picked look contributes no appearance.
                PrimaryRegion(region: .newYork, appearance: nil, order: 1),
            ])
        }

        let snapshot = try await reader
            .snapshot(asOf: WhereCoreTestSupport.iso("2026-03-15T12:00:00-07:00"))

        #expect(snapshot.appearances == [.california: caLook])
    }

    @Test func snapshotAppearancesSurviveCodableRoundTrip() throws {
        let look = RegionAppearance(color: .indigo, emoji: "🗽", symbolName: "building.2.fill")
        let snapshot = WidgetSnapshot(
            day: WhereCoreTestSupport.iso("2026-03-15T00:00:00-07:00"),
            year: 2026,
            dayRegions: [.newYork],
            totals: [.newYork: 3],
            appearances: [.newYork: look],
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)
        #expect(decoded == snapshot)
        #expect(decoded.appearances == [.newYork: look])
    }

    @Test func samplesAndManualDaysRollUpLikeTheYearReport() async throws {
        let (reader, store) = try Self.makeReader()
        try await store.perform {
            // Two same-day samples in CA, one in NY the next day.
            try await store.add(sample: Self.sample(
                at: "2026-03-15T09:00:00-07:00",
                latitude: 37.7749,
                longitude: -122.4194,
            ))
            try await store.add(sample: Self.sample(
                at: "2026-03-15T18:00:00-07:00",
                latitude: 34.0522,
                longitude: -118.2437,
            ))
            try await store.add(sample: Self.sample(
                at: "2026-03-16T12:00:00-04:00",
                latitude: 40.7128,
                longitude: -74.0060,
            ))
            // A manual backfill for a third day.
            try await store.setManualDay(DayPresence(
                date: WhereCoreTestSupport.iso("2026-05-01T00:00:00-07:00"),
                in: WhereCoreTestSupport.calendar(),
                regions: [.canada],
            ))
        }

        let snapshot = try await reader
            .snapshot(asOf: WhereCoreTestSupport.iso("2026-03-15T20:00:00-07:00"))

        #expect(snapshot.year == 2026)
        #expect(snapshot.dayRegions == [.california])
        #expect(snapshot.totals == [.california: 1, .newYork: 1, .canada: 1])
    }

    @Test func dayRegionsAreEmptyWhenTodayHasNoData() async throws {
        let (reader, store) = try Self.makeReader()
        try await store.perform {
            try await store.add(sample: Self.sample(
                at: "2026-03-15T09:00:00-07:00",
                latitude: 37.7749,
                longitude: -122.4194,
            ))
        }

        let snapshot = try await reader
            .snapshot(asOf: WhereCoreTestSupport.iso("2026-03-20T08:00:00-07:00"))

        #expect(snapshot.dayRegions.isEmpty)
        #expect(snapshot.totals == [.california: 1])
    }

    @Test func totalsOnlyCoverTheSnapshotsYear() async throws {
        let (reader, store) = try Self.makeReader()
        try await store.perform {
            try await store.add(sample: Self.sample(
                at: "2025-12-31T12:00:00-08:00",
                latitude: 37.7749,
                longitude: -122.4194,
            ))
            try await store.add(sample: Self.sample(
                at: "2026-01-01T12:00:00-08:00",
                latitude: 40.7128,
                longitude: -74.0060,
            ))
        }

        let in2026 = try await reader
            .snapshot(asOf: WhereCoreTestSupport.iso("2026-01-01T20:00:00-08:00"))
        #expect(in2026.totals == [.newYork: 1])
        #expect(in2026.dayRegions == [.newYork])

        let in2025 = try await reader
            .snapshot(asOf: WhereCoreTestSupport.iso("2025-12-31T20:00:00-08:00"))
        #expect(in2025.totals == [.california: 1])
        #expect(in2025.dayRegions == [.california])
    }

    @Test func authoritativeManualDayReplacesGPSInDayRegions() async throws {
        let (reader, store) = try Self.makeReader()
        try await store.perform {
            try await store.add(sample: Self.sample(
                at: "2026-03-15T09:00:00-07:00",
                latitude: 37.7749,
                longitude: -122.4194,
            ))
            try await store.setManualDay(DayPresence(
                date: WhereCoreTestSupport.iso("2026-03-15T07:00:00-07:00"),
                in: WhereCoreTestSupport.calendar(),
                regions: [.newYork],
                isAuthoritative: true,
            ))
        }

        let snapshot = try await reader
            .snapshot(asOf: WhereCoreTestSupport.iso("2026-03-15T20:00:00-07:00"))

        #expect(snapshot.dayRegions == [.newYork])
        #expect(snapshot.totals == [.newYork: 1])
    }
}
