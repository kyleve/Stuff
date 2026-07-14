import Foundation
import RegionKit
import TestHostSupport
import Testing
@_spi(Testing) import WhereCore
@_spi(Testing) @testable import WhereUI

/// Covers `ResolveModel` — the Resolve tab's issue list and dismiss action.
@MainActor
struct ResolveModelTests {
    private func date(year: Int, month: Int, day: Int) -> Date {
        Calendar.current.date(
            from: DateComponents(year: year, month: month, day: day, hour: 12),
        )!
    }

    @Test func loadPopulatesMissingDayIssues() async throws {
        let store = try TestStore()
        let now = date(year: 2026, month: 2, day: 10)
        let services = WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(),
            reminderScheduler: NoopLoggingReminderScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
            now: { now },
        )
        let resolve = ResolveModel(
            services: services,
            preferences: WherePreferences(store: InMemoryKeyValueStore()),
        )

        try await services.journal.addManualDay(
            date: date(year: 2026, month: 1, day: 1),
            regions: [.california],
            audit: nil,
        )
        await resolve.load(year: 2026, primaryRegions: [.california])

        #expect(!resolve.dataIssues.isEmpty)
        #expect(resolve.dataIssues.contains { $0.category == .missingDays })
    }

    @Test func dismissWritesToStoreAndRemovesRow() async throws {
        let store = try TestStore()
        let now = date(year: 2026, month: 6, day: 15)
        let services = WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(),
            reminderScheduler: NoopLoggingReminderScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
            now: { now },
        )
        let resolve = ResolveModel(
            services: services,
            preferences: WherePreferences(store: InMemoryKeyValueStore()),
        )

        // Two calendar-adjacent days with disjoint regions produce a real,
        // dismissible abrupt-change issue, so `dismiss` runs against an issue the
        // scanner actually returned from `load(...)` — no seeded fixture, no
        // `setDataIssues` short-circuit.
        try await services.journal.addManualDay(
            date: date(year: 2026, month: 3, day: 1),
            regions: [.california],
            audit: nil,
        )
        try await services.journal.addManualDay(
            date: date(year: 2026, month: 3, day: 2),
            regions: [.newYork],
            audit: nil,
        )
        await resolve.load(year: 2026, primaryRegions: [.california, .newYork])

        let issue = try #require(resolve.dataIssues.first { $0.isDismissible })
        await resolve.dismiss(issue)
        #expect(!resolve.dataIssues.contains { $0.id == issue.id })

        let keys = try await store.dismissedIssueKeys()
        #expect(keys.contains(issue.id.storageKey))
    }

    /// End-to-end: seeded cruise-speed GPS fixes for one day surface a
    /// `.flightDay` issue through the real scanner, keeping the endpoints and
    /// dropping the fly-over `.other`.
    @Test func loadSurfacesFlightDayIssue() async throws {
        let store = try TestStore()
        let now = date(year: 2026, month: 6, day: 15)
        let services = WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(),
            reminderScheduler: NoopLoggingReminderScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
            now: { now },
        )
        let resolve = ResolveModel(
            services: services,
            preferences: WherePreferences(store: InMemoryKeyValueStore()),
        )

        let jfk = Coordinate(latitude: 40.6413, longitude: -73.7781)
        let sfo = Coordinate(latitude: 37.6213, longitude: -122.3790)
        let illinois = Coordinate(latitude: 40.29, longitude: -90.39)
        let colorado = Coordinate(latitude: 39.53, longitude: -106.16)
        let nevada = Coordinate(latitude: 38.68, longitude: -116.90)
        let fixes: [(Double, Coordinate)] = [
            (8.0, jfk),
            (8.5, jfk),
            (12.0, jfk),
            (13.5, illinois),
            (15.0, colorado),
            (16.5, nevada),
            (17.5, sfo),
            (18.0, sfo),
        ]
        try await store.perform {
            for (hour, coordinate) in fixes {
                try await store.add(sample: LocationSample(
                    timestamp: flightSampleDate(hour: hour),
                    coordinate: coordinate,
                    horizontalAccuracy: 20,
                    source: .gpsSignificantChange,
                ))
            }
        }
        await resolve.load(year: 2026, primaryRegions: [.california, .newYork])

        let flight = try #require(resolve.dataIssues.first { $0.category == .flightDay })
        guard case let .correctFlightDay(_, keep, removed, peak) = flight.resolution else {
            Issue.record("expected correctFlightDay resolution")
            return
        }
        #expect(keep == [.newYork, .california])
        #expect(removed == [.other])
        #expect(peak > 300)
    }

    private func flightSampleDate(hour: Double) -> Date {
        let wholeHour = Int(hour)
        let minutes = Int((hour - Double(wholeHour)) * 60)
        return Calendar.current.date(from: DateComponents(
            year: 2026,
            month: 3,
            day: 15,
            hour: wholeHour,
            minute: minutes,
        ))!
    }

    /// The empty-state guard: `hasLoaded` starts false and flips once the first
    /// scan lands, so `ResolutionView` can hold a spinner instead of flashing
    /// "all clear" under a non-zero badge.
    @Test func loadMarksTheModelLoaded() async throws {
        let store = try TestStore()
        let now = date(year: 2026, month: 2, day: 10)
        let services = WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(),
            reminderScheduler: NoopLoggingReminderScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
            now: { now },
        )
        let resolve = ResolveModel(
            services: services,
            preferences: WherePreferences(store: InMemoryKeyValueStore()),
        )

        #expect(!resolve.hasLoaded)
        await resolve.load(year: 2026, primaryRegions: [.california])
        #expect(resolve.hasLoaded)
    }

    /// Seeding a fixture also counts as loaded, so the seeded "empty" preview
    /// renders its empty state rather than a stuck spinner.
    @Test func seedingMarksTheModelLoaded() throws {
        let store = try TestStore()
        let services = WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(),
            reminderScheduler: NoopLoggingReminderScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
        )
        let resolve = ResolveModel(
            services: services,
            preferences: WherePreferences(store: InMemoryKeyValueStore()),
        )

        resolve.setDataIssues([])
        #expect(resolve.hasLoaded)
    }
}
