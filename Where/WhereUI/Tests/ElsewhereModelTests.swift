import Foundation
import RegionKit
import TestHostSupport
import Testing
import WhereCore
@testable import WhereUI

@MainActor
struct ElsewhereModelTests {
    @Test func newerSameYearInputWinsEvenWhenTheOlderReadFinishesLast() async throws {
        let resolver = HeldElsewhereResolver()
        let model = ElsewhereModel(resolver: resolver, namer: EmptyPlaceNamer())
        let input = ElsewhereModelTestSupport.input()
        let first = Task { await model.refresh(input) }
        try await ElsewhereModelTestSupport.waitForRequests(1, in: resolver)
        let nextInput = ElsewhereModelTestSupport.input(region: .canada)
        let next = Task { await model.refresh(nextInput) }
        try await ElsewhereModelTestSupport.waitForRequests(2, in: resolver)
        await resolver.complete(
            1,
            with: .success(ElsewhereModelTestSupport.result(nextInput, region: .canada)),
        )
        await next.value
        await resolver.complete(
            0,
            with: .success(ElsewhereModelTestSupport.result(input, region: .other)),
        )
        await first.value
        #expect(model.content(for: 2026)?.regions.map(\.region) == [.canada])
    }

    @Test func cancelledResolutionCannotPublishAfterLeavingTheTab() async throws {
        let resolver = HeldElsewhereResolver()
        let model = ElsewhereModel(resolver: resolver, namer: EmptyPlaceNamer())
        let input = ElsewhereModelTestSupport.input()
        let task = Task { await model.refresh(input) }
        try await ElsewhereModelTestSupport.waitForRequests(1, in: resolver)
        task.cancel()
        await resolver.complete(
            0,
            with: .success(ElsewhereModelTestSupport.result(input, region: .other)),
        )
        await task.value
        #expect(model.content(for: 2026) == nil)
        #expect(model.failure(for: 2026) == nil)
    }

    @Test func yearChangesInvalidatePendingContent() async throws {
        let resolver = HeldElsewhereResolver()
        let model = ElsewhereModel(resolver: resolver, namer: EmptyPlaceNamer())
        let input = ElsewhereModelTestSupport.input()
        let task = Task { await model.refresh(input) }
        try await ElsewhereModelTestSupport.waitForRequests(1, in: resolver)
        model.invalidate()
        await resolver.complete(
            0,
            with: .success(ElsewhereModelTestSupport.result(input, region: .other)),
        )
        await task.value
        #expect(model.content(for: 2026) == nil)
        #expect(model.content(for: 2025) == nil)
    }

    @Test func failedRefreshRetainsContentAndRetryCanReplaceIt() async throws {
        let resolver = HeldElsewhereResolver()
        let model = ElsewhereModel(resolver: resolver, namer: EmptyPlaceNamer())
        let input = ElsewhereModelTestSupport.input()
        let first = Task { await model.refresh(input) }
        try await ElsewhereModelTestSupport.waitForRequests(1, in: resolver)
        await resolver.complete(
            0,
            with: .success(ElsewhereModelTestSupport.result(input, region: .other)),
        )
        await first.value

        let nextInput = ElsewhereModelTestSupport.input(region: .canada)
        let next = Task { await model.refresh(nextInput) }
        try await ElsewhereModelTestSupport.waitForRequests(2, in: resolver)
        await resolver.complete(1, with: .failure(TestHostError("Fixture read failed")))
        await next.value
        #expect(model.content(for: 2026)?.regions.map(\.region) == [.other])
        #expect(model.failure(for: 2026) != nil)
        #expect(model.content(for: 2025) == nil)

        let retry = Task { await model.refresh(nextInput) }
        try await ElsewhereModelTestSupport.waitForRequests(3, in: resolver)
        await resolver.complete(
            2,
            with: .success(ElsewhereModelTestSupport.result(nextInput, region: .canada)),
        )
        await retry.value
        #expect(model.content(for: 2026)?.regions.map(\.region) == [.canada])
        #expect(model.failure(for: 2026) == nil)
    }

    @Test func catalogNamesAndCountsRemainAvailableWithoutGeocoding() async throws {
        let report = PreviewSupport.elsewhereCatalogYearReportModel()
        let input = try #require(report.elsewhereInput)
        let model = ElsewhereModel(resolver: report.services.elsewhere, namer: EmptyPlaceNamer())
        await model.refresh(input)
        let content = try #require(model.content(for: report.selectedYear))
        #expect(try content.regions.map(\.region) == [
            #require(Region(rawValue: "us-NV")),
            #require(Region(rawValue: "us-OR")),
            .canada,
            .other,
        ])
        #expect(content.regions.map(\.days.count) == [2, 1, 1, 1])
        #expect(content.placeNames.isEmpty)
        for region in content.regions {
            #expect(content.cardLocations.pointsByRegion[region.region]
                == region.locations.flatMap(\.points))
        }
        #expect(content.cardLocations.pointsByRegion[.other]?.isEmpty == true)
        #expect(report.report?.totals == [.other: 5])
    }

    @Test func stalePlaceNamesCannotReplaceANewerYear() async throws {
        let report = PreviewSupport.elsewhereCatalogYearReportModel()
        let namer = HeldPlaceNamer()
        let model = ElsewhereModel(resolver: report.services.elsewhere, namer: namer)
        let input = try #require(report.elsewhereInput)
        let first = Task { await model.refresh(input) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while await !namer.isWaiting {
            guard ContinuousClock.now < deadline
            else { throw TestHostError("Place lookup did not start") }
            try await Task.sleep(for: .milliseconds(5))
        }
        // Catalog counts are visible before an optional network lookup finishes.
        #expect(model.content(for: 2026)?.regions.count == 4)
        await model.refresh(ElsewhereModelTestSupport.input(year: 2025, region: .canada))
        await namer.complete("Stale city")
        await first.value
        #expect(model.content(for: 2026) == nil)
        #expect(model.content(for: 2025)?.regions.map(\.region) == [.canada])
        #expect(model.content(for: 2025)?.placeNames.isEmpty == true)
        #expect(model.cachedPlaceName(for: ElsewherePreview.vegas) == nil)
    }

    @Test func cardPlaceNamesAreAvailableToDayRowsAfterResolution() async throws {
        let report = PreviewSupport.elsewhereCatalogYearReportModel()
        let input = try #require(report.elsewhereInput)
        let model = ElsewhereModel(resolver: report.services.elsewhere, namer: PreviewPlaceNamer())
        await model.refresh(input)
        let nevada = try #require(Region(rawValue: "us-NV"))
        let cardName = try #require(model.content(for: report.selectedYear)?.placeNames[nevada])
        #expect(model.cachedPlaceName(for: ElsewherePreview.vegas) == cardName)
        #expect(await model.placeName(for: ElsewherePreview.vegas) == cardName)
    }

    @Test func coordinateOnlyChangesRefreshCardsAndMapPoints() async throws {
        let report = PreviewSupport.elsewhereCatalogYearReportModel()
        let input = try #require(report.elsewhereInput)
        let firstID = try #require(input.history.samples.first?.sample.id)
        let history = input.history.samples.map { entry in
            guard entry.sample.id == firstID else { return entry }
            return AttributedLocationSample(
                sample: LocationSample(
                    id: entry.sample.id,
                    timestamp: entry.sample.timestamp,
                    coordinate: ElsewherePreview.portland,
                    horizontalAccuracy: 10,
                    source: entry.sample.source,
                ),
                regions: entry.regions,
            )
        }
        let changed = ElsewhereInput(
            report: input.report,
            primaryRegions: input.primaryRegions,
            history: LocationHistoryProjection(
                samples: history,
                revisions: input.history.revisions,
            ),
            manualDays: input.manualDays,
            calendar: input.calendar,
        )
        let model = ElsewhereModel(resolver: report.services.elsewhere, namer: EmptyPlaceNamer())
        await model.refresh(input)
        let nevada = try #require(Region(rawValue: "us-NV"))
        let oregon = try #require(Region(rawValue: "us-OR"))
        #expect(model.content(for: 2026)?.regions.first?.region == nevada)
        let originalLocations = try #require(model.content(for: 2026)?.cardLocations)
        await model.refresh(input)
        #expect(model.content(for: 2026)?.cardLocations.id == originalLocations.id)
        await model.refresh(changed)
        let leading = try #require(model.content(for: 2026)?.regions.first)
        #expect(leading.region == oregon)
        #expect(leading.days.count == 2)
        #expect(leading.locations.map(\.day) == leading.days.map(\.day))
        #expect(leading.locations.flatMap(\.points)
            .allSatisfy { $0.coordinate == ElsewherePreview.portland })
        #expect(changed.report == input.report)
        let updatedLocations = try #require(model.content(for: 2026)?.cardLocations)
        #expect(updatedLocations.id != originalLocations.id)
        #expect(updatedLocations.pointsByRegion[oregon] == leading.locations.flatMap(\.points))
    }
}
