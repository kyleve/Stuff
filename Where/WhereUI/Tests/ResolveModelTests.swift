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
            preferences: makePreferences(),
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
            preferences: makePreferences(),
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

        let ids = try await store.dismissedIssueIDs()
        #expect(ids.contains(issue.id))
    }

    /// End-to-end: seeded cruise-speed GPS fixes for one day surface a
    /// `.flightDay` issue through the real scanner, keeping the endpoints and
    /// dropping the fly-over `.other`.
    @Test func loadSurfacesFlightDayIssue() async throws {
        let store = try TestStore()
        let now = date(year: 2026, month: 6, day: 15)
        let services = FlightReviewTestSupport.services(store: store, now: now)
        let resolve = ResolveModel(
            services: services,
            preferences: makePreferences(),
        )

        try await FlightReviewTestSupport.seed(into: store, includeArrival: true)
        await resolve.load(year: 2026, primaryRegions: [.california, .newYork])

        let flight = try #require(resolve.dataIssues.first { $0.category == .flightDay })
        guard case let .correctSamples(proposal) = flight.resolution else {
            Issue.record("expected sample correction resolution")
            return
        }
        #expect(proposal.resultingRegions == [.newYork, .california])
        #expect(!proposal.edits.isEmpty)
        #expect(resolve.review(for: flight)?.flight?.peakSpeedKMH ?? 0 > 450)
    }

    /// Applying reviewed samples clears the actionable issue while retaining
    /// the completed flight information.
    @Test func applyingFlightFixClearsTheIssue() async throws {
        let store = try TestStore()
        let now = date(year: 2026, month: 6, day: 15)
        let services = FlightReviewTestSupport.services(store: store, now: now)
        let resolve = ResolveModel(
            services: services,
            preferences: makePreferences(),
        )

        try await FlightReviewTestSupport.seed(into: store, includeArrival: true)
        await resolve.load(year: 2026, primaryRegions: [.california, .newYork])

        let flight = try #require(resolve.dataIssues.first { $0.category == .flightDay })
        guard case let .correctSamples(proposal) = flight.resolution else {
            Issue.record("expected sample correction resolution")
            return
        }
        let result = try await services.corrections.apply(proposal)
        guard case .applied = result else {
            Issue.record("expected correction to apply")
            return
        }
        await services.resolution.invalidate()
        await resolve.load(year: 2026, primaryRegions: [.california, .newYork])

        #expect(!resolve.dataIssues.contains { $0.category == .flightDay })
    }

    @Test func ongoingFlightRemainsReviewableWithoutAnActionableFlightIssue() async throws {
        let store = try TestStore()
        let services = FlightReviewTestSupport.services(
            store: store,
            now: FlightReviewTestSupport.date(hour: 16.5),
        )
        let resolve = ResolveModel(services: services, preferences: makePreferences())
        try await FlightReviewTestSupport.seed(into: store, includeArrival: false)

        await resolve.load(year: 2026, primaryRegions: [.newYork, .california])

        #expect(resolve.dataIssues.allSatisfy { $0.category != .flightDay })
        #expect(resolve.pendingReviews.count == 1)
        #expect(resolve.pendingReviews.first?.proposal == nil)
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
            preferences: makePreferences(),
        )

        #expect(!resolve.hasLoaded)
        await resolve.load(year: 2026, primaryRegions: [.california])
        #expect(resolve.hasLoaded)
    }

    /// Both `PreviewSupport.resolveModel` modes come back loaded, so a preview or
    /// snapshot renders the state it asked for on its first frame. The empty mode
    /// used to skip seeding entirely, leaving `hasLoaded` false — indistinguishable
    /// from "the first scan hasn't landed", so `ResolutionView` showed the loading
    /// placeholder and then whatever a live scan of the empty store found. That
    /// made `resolution.Empty`'s capture a race, which CI lost once the snapshot
    /// pipeline stopped spending a spare second per image.
    @Test(arguments: [true, false])
    func theResolveFixtureIsLoadedUpFront(seededWithIssues: Bool) {
        let resolve = PreviewSupport.resolveModel(seededWithIssues: seededWithIssues)

        #expect(resolve.hasLoaded)
        #expect(resolve.dataIssues.isEmpty == !seededWithIssues)
    }

    /// A seeded fixture survives the `load(...)` that `ResolutionView`'s
    /// `.task(id:)` fires on appear. This is what keeps the empty fixture empty:
    /// the same store the scan runs against here has no logged days, so an
    /// un-short-circuited scan would fill the list with missing-day issues and
    /// `resolution.Empty` would capture a populated list instead.
    @Test func loadLeavesASeededFixtureAlone() async throws {
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
            preferences: makePreferences(),
        )

        resolve.setDataIssues([])
        await resolve.load(year: 2026, primaryRegions: [.california])

        #expect(resolve.dataIssues.isEmpty)
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
            preferences: makePreferences(),
        )

        resolve.setDataIssues([])
        #expect(resolve.hasLoaded)
    }
}
