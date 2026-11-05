import Foundation
import RegionKit
import Testing
@testable import WhereCore

struct WidgetDataReaderTests {
    private static func makeReader() throws -> (WidgetDataReader, SwiftDataStore) {
        let store = try SwiftDataStore.inMemory()
        let reader = WidgetDataReader(
            store: store,
            history: LocationHistoryReader(
                store: store,
                policy: .foundation,
                geography: HistoryRegionAttribution(),
            ),
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
            recordingDay: nil,
        )
    }

    @Test func incompleteYearCanPublishAClearDayAndResolvesAfterASourceChoice() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let samples = try LocationHistoryReaderTestSupport.competingTracks()
        try await LocationHistoryReaderTestSupport.add(samples, to: store)
        let calendar = LocationHistoryReaderTestSupport.calendar
        let reader = WidgetDataReader(
            store: store,
            history: LocationHistoryReaderTestSupport.reader(store),
            aggregator: DayAggregator(calendar: calendar, timeZone: calendar.timeZone),
        )
        let date = Date(timeIntervalSinceReferenceDate: 7200)
        let disputed = try await reader.snapshot(asOf: date)
        #expect(disputed.assessment?.version == RecordingEvidencePolicy.version)
        #expect(disputed.assessment?.dayRegions == .needsReview)
        #expect(disputed.assessment?.totals == .needsReview)
        let clear = try await reader.snapshot(asOf: date.addingTimeInterval(2 * 86400))
        #expect(clear.assessment?.dayRegions == .complete([]))
        #expect(clear.assessment?.totals == .needsReview)
        try await RecordingChoiceTestSupport.append(
            .source(RecordingAssessmentTestSupport.decision(990, end: 1201)),
            store: store,
        )
        let resolved = try await reader.snapshot(asOf: date)
        #expect(resolved.assessment?.dayRegions == .complete([.california]))
        #expect(resolved.assessment?.totals == .complete([.california: 1]))
    }

    @Test func recordedDatesDriveWidgetYearAcrossViewingZones() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let sample = try LocationHistoryReaderTestSupport.sample(
            seconds: 1800,
            zone: #require(TimeZone(secondsFromGMT: -3600)),
        )
        try await LocationHistoryReaderTestSupport.add([sample], to: store)
        for hours in [-12, 0, 14] {
            var calendar = LocationHistoryReaderTestSupport.calendar
            calendar.timeZone = try #require(TimeZone(secondsFromGMT: hours * 3600))
            let day = CalendarDay(year: 2000, month: 12, day: 31)
            let reader = WidgetDataReader(
                store: store,
                history: LocationHistoryReaderTestSupport.reader(store),
                aggregator: DayAggregator(calendar: calendar, timeZone: calendar.timeZone),
            )
            let snapshot = try await reader.snapshot(asOf: day.startOfDay(in: calendar))
            #expect(snapshot.day == day)
            #expect(snapshot.year == 2000)
            #expect(snapshot.assessment?.dayRegions == .complete([.california]))
            #expect(snapshot.assessment?.totals == .complete([.california: 1]))
        }
    }

    @Test func emptyStoreYieldsEmptySnapshot() async throws {
        let (reader, _) = try Self.makeReader()

        let snapshot = try await reader
            .snapshot(asOf: WhereCoreTestSupport.iso("2026-03-15T12:00:00-07:00"))

        #expect(snapshot.year == 2026)
        #expect(snapshot.assessment?.dayRegions == .complete([]))
        #expect(snapshot.assessment?.totals == .complete([:]))
        #expect(snapshot.appearances.isEmpty)
    }

    @Test func snapshotCarriesPickedRegionAppearances() async throws {
        let (reader, store) = try Self.makeReader()
        let caLook = RegionAppearance(color: .orange, emoji: "🌴", symbolName: .sunMaxFill)
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
        #expect(snapshot.assessment?.dayRegions == .complete([.california]))
        #expect(snapshot.assessment?.totals == .complete([.california: 1, .newYork: 1, .canada: 1]))
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

        #expect(snapshot.assessment?.dayRegions == .complete([]))
        #expect(snapshot.assessment?.totals == .complete([.california: 1]))
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
        #expect(in2026.assessment?.totals == .complete([.newYork: 1]))
        #expect(in2026.assessment?.dayRegions == .complete([.newYork]))

        let in2025 = try await reader
            .snapshot(asOf: WhereCoreTestSupport.iso("2025-12-31T20:00:00-08:00"))
        #expect(in2025.assessment?.totals == .complete([.california: 1]))
        #expect(in2025.assessment?.dayRegions == .complete([.california]))
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

        #expect(snapshot.assessment?.dayRegions == .complete([.newYork]))
        #expect(snapshot.assessment?.totals == .complete([.newYork: 1]))
    }
}
