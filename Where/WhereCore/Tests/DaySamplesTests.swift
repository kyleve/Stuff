import Foundation
import RegionKit
import Testing
@testable import WhereCore

/// Covers `DaySamples` — the lazy, GPS-only per-day grouping the flight detector
/// walks. `calendar` is pinned to America/Los_Angeles so day bucketing doesn't
/// shift with the test runner's zone.
struct DaySamplesTests {
    private let calendar = WhereCoreTestSupport.calendar()

    private func fix(
        _ iso: String,
        source: SampleSource = .gpsSignificantChange,
    ) -> LocationSample {
        LocationSample(
            timestamp: WhereCoreTestSupport.iso(iso),
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 10,
            source: source,
        )
    }

    @Test func groupsGpsFixesByDaySortedByTimestamp() {
        // Supplied out of order; the same day's fixes come back ascending.
        let later = fix("2026-07-14T18:00:00Z")
        let earlier = fix("2026-07-14T15:00:00Z")
        let daySamples = DaySamples(samples: [later, earlier], calendar: calendar)

        let result = daySamples.samples(on: CalendarDay(year: 2026, month: 7, day: 14))
        #expect(result.map(\.timestamp) == [earlier.timestamp, later.timestamp])
    }

    @Test func excludesManualAndEvidenceSamples() {
        // Manual / evidence-implied timestamps are user-asserted, so a speed
        // computed across them is meaningless — they must not appear.
        let gps = fix("2026-07-14T18:00:00Z")
        let manual = fix("2026-07-14T19:00:00Z", source: .manual)
        let evidence = fix(
            "2026-07-14T20:00:00Z",
            source: .evidenceImplied(id: UUID(), kind: .other(nil)),
        )
        let daySamples = DaySamples(samples: [gps, manual, evidence], calendar: calendar)

        let result = daySamples.samples(on: CalendarDay(year: 2026, month: 7, day: 14))
        #expect(result.count == 1)
        #expect(result.first?.source == .gpsSignificantChange)
    }

    @Test func returnsEmptyForADayWithNoFixes() {
        let daySamples = DaySamples(samples: [fix("2026-07-14T18:00:00Z")], calendar: calendar)
        #expect(daySamples.samples(on: CalendarDay(year: 2026, month: 1, day: 1)).isEmpty)
    }

    @Test func bucketsByCalendarDayInTheGivenTimeZone() {
        // 05:00Z is 22:00 the prior day in Pacific; 08:00Z is 01:00 the next day.
        let late14 = fix("2026-07-15T05:00:00Z") // 2026-07-14 22:00 PDT
        let early15 = fix("2026-07-15T08:00:00Z") // 2026-07-15 01:00 PDT
        let daySamples = DaySamples(samples: [late14, early15], calendar: calendar)

        #expect(
            daySamples.samples(on: CalendarDay(year: 2026, month: 7, day: 14))
                .map(\.timestamp) == [late14.timestamp],
        )
        #expect(
            daySamples.samples(on: CalendarDay(year: 2026, month: 7, day: 15))
                .map(\.timestamp) == [early15.timestamp],
        )
    }

    /// The grouping is memoized (built once, behind a lock); repeated reads must
    /// stay consistent regardless of which day is asked for first.
    @Test func repeatedReadsAreConsistent() {
        let a = fix("2026-07-14T15:00:00Z")
        let b = fix("2026-07-14T18:00:00Z")
        let daySamples = DaySamples(samples: [a, b], calendar: calendar)
        let day = CalendarDay(year: 2026, month: 7, day: 14)

        // Ask an empty day first (forces the grouping), then the populated one.
        #expect(daySamples.samples(on: CalendarDay(year: 2026, month: 1, day: 1)).isEmpty)
        #expect(daySamples.samples(on: day).map(\.timestamp) == [a.timestamp, b.timestamp])
        #expect(daySamples.samples(on: day).map(\.timestamp) == [a.timestamp, b.timestamp])
    }
}
