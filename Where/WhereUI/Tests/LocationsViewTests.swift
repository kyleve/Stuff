import SwiftUI
import TestHostSupport
import Testing
import WhereCore
@_spi(Testing) @testable import WhereUI

/// Both tests resize native navigation in the shared test host window.
@MainActor
@Suite(.serialized)
struct LocationsViewTests {
    @Test func initialBrowsePositionFollowsInsetsUntilARegionIsRestored() async throws {
        let world = try await WhereFlyoverWorld.build()
        let navigation = SceneNavigationModel.Locations()
        let host = UIHostingController(rootView: LocationsBrowsePane(
            report: world.report,
            navigation: navigation,
        )
        .dynamicTypeSize(.accessibility5)
        .whereBroadwayRoot())

        try await show(host) { controller in
            controller.view.frame = CGRect(x: 0, y: 0, width: 466, height: 678)
            controller.traitOverrides.horizontalSizeClass = .compact
            controller.view.layoutIfNeeded()
            try await waitForAsync {
                AdaptiveHistoryTestSupport.descendants(
                    of: controller.view,
                    matching: UIScrollView.self,
                ).contains { $0.contentSize.height > $0.bounds.height }
            }
            let scroll = try #require(AdaptiveHistoryTestSupport.descendants(
                of: controller.view,
                matching: UIScrollView.self,
            ).first { $0.contentSize.height > $0.bounds.height })
            for topInset in [CGFloat(82), 0, 56, 0] {
                let previousInset = scroll.adjustedContentInset.top
                controller.additionalSafeAreaInsets.top = topInset
                controller.view.layoutIfNeeded()
                try await waitForAsync {
                    abs(scroll.adjustedContentInset.top - previousInset) > 1
                        && abs(scroll.contentOffset.y + scroll.adjustedContentInset.top) < 1
                }
            }
            navigation.visibleRegion = .california
            navigation.restoreBrowsePosition()
            try await waitForAsync {
                scroll.contentOffset.y + scroll.adjustedContentInset.top > 100
            }
            #expect(navigation.selectedRegion == nil)
        }
    }

    @Test func foldingDuringLoadingAndAYearChangeDoesNotRestartOrPublishTheOlderRead() async throws {
        let store = try TestStore()
        let report = PlanningTestSupport.report(store: store)
        let calendar = report.calendar
        try await report.services.journal.addManualDay(
            date: CalendarDay(year: 2024, month: 3, day: 1).startOfDay(in: calendar),
            regions: [.newYork],
            audit: nil,
        )
        try await report.services.journal.addManualDay(
            date: CalendarDay(year: 2026, month: 3, day: 1).startOfDay(in: calendar),
            regions: [.california],
            audit: nil,
        )
        await store.enableFirstSamplesGate()
        let olderRead = Task { await report.select(year: 2024) }
        await store.awaitFirstSamplesCall()
        let navigation = SceneNavigationModel.Locations()
        navigation.select(region: .california)
        let state = AdaptiveHistoryHostState()
        let host = UIHostingController(rootView: AdaptiveHistoryHostedSurface(state: state) {
            LocationsView(report: report, navigation: navigation)
        })
        host.safeAreaRegions = []
        do {
            try await show(host) { controller in
                let readsBeforeFolding = await store.sampleReadCount
                for pose in [
                    AdaptiveHistoryPose.outerPortrait,
                    .innerPortrait,
                    .tabletop,
                    .outerPortrait,
                ] {
                    try await AdaptiveHistoryTestSupport.resize(controller, state: state, to: pose)
                    #expect(await store.sampleReadCount == readsBeforeFolding)
                    #expect(report.loadState == .loading)
                }
                await report.select(year: 2026)
                let readsAfterYearChange = await store.sampleReadCount
                for pose in [AdaptiveHistoryPose.innerLandscape, .tabletop, .outerPortrait] {
                    try await AdaptiveHistoryTestSupport.resize(controller, state: state, to: pose)
                    #expect(await store.sampleReadCount == readsAfterYearChange)
                }
                await store.releaseFirstSamplesCall()
                await olderRead.value
                #expect(report.selectedYear == 2026)
                #expect(report.report?.year == 2026)
                #expect(report.report?.totals[.california] == 1)
                #expect(report.report?.totals[.newYork] == nil)
                #expect(report.loadState == .loaded)
                #expect(navigation.selectedRegion == .california)
            }
        } catch {
            await store.releaseFirstSamplesCall()
            await olderRead.value
            throw error
        }
    }
}
