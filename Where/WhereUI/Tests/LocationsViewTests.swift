import BroadwayUI
import RegionKit
import SnapshotKit
import SwiftUI
import TestHostSupport
import Testing
import WhereCore
@testable import WhereUI

struct LocationsViewTests {
    @Test func screenCompositionKeepsViewValuesWithinStackBudget() {
        #expect(MemoryLayout<LocationsView.Body>.size < 16384)
    }
}

/// These tests resize native navigation in the shared test host window.
@MainActor
@Suite(.serialized)
struct LocationsViewTestsDuo {
    @Test func initialBrowsePositionFollowsInsetsUntilARegionIsRestored() async throws {
        let world = try await WhereFlyoverWorld.build()
        let navigation = LocationsView.Navigation()
        let store = BScrollRestorationStore()
        let capture = ScrollPositionCapture()
        let host = UIHostingController(rootView: LocationsBrowsePane(
            report: world.report,
            navigation: navigation,
        )
        .overlay { ScrollPositionProbe(
            LocationsCardsView.self,
            role: LocationsCardsView.ScrollRole.browse,
            context: world.report.selectedYear,
            idType: Region.self,
            capture: capture,
        ) }
        .bScrollRestorationScope(store)
        .dynamicTypeSize(.accessibility5)
        .whereBroadwayRoot())

        try await show(host) { controller in
            controller.view.frame = CGRect(x: 0, y: 0, width: 466, height: 678)
            controller.traitOverrides.horizontalSizeClass = .compact
            controller.view.layoutIfNeeded()
            try await waitForStage("initial scroll content") {
                AdaptivePaneTestSupport.descendants(
                    of: controller.view,
                    matching: UIScrollView.self,
                ).contains { $0.contentSize.height > $0.bounds.height }
            }
            var scroll = try #require(AdaptivePaneTestSupport.descendants(
                of: controller.view,
                matching: UIScrollView.self,
            ).first { $0.contentSize.height > $0.bounds.height })
            @MainActor func currentScroll() -> UIScrollView? {
                AdaptivePaneTestSupport.descendants(
                    of: controller.view,
                    matching: UIScrollView.self,
                )
                .first { $0.window != nil && $0.contentSize.height > $0.bounds.height }
            }
            for topInset in [CGFloat(82), 0, 56, 0] {
                let previousInset = scroll.adjustedContentInset.top
                controller.additionalSafeAreaInsets.top = topInset
                controller.view.setNeedsLayout()
                controller.view.window?.layoutIfNeeded()
                do {
                    try await waitForStage(
                        "top anchoring after inset \(previousInset) -> requested \(topInset)",
                    ) {
                        guard let current = currentScroll() else { return false }
                        return abs(current.adjustedContentInset.top - previousInset) > 1
                            && abs(current.contentOffset.y + current.adjustedContentInset.top) < 1
                    }
                } catch {
                    throw TestHostError(
                        "\(error); adjusted=\(scroll.adjustedContentInset), offset=\(scroll.contentOffset), bounds=\(scroll.bounds), content=\(scroll.contentSize), attached=\(scroll.window != nil), current=\(String(describing: currentScroll()))",
                    )
                }
                let current = try #require(currentScroll())
                scroll = current
            }
            let position = try #require(capture.binding)
            position.wrappedValue.scrollTo(id: Region.california, anchor: .top)
            try await waitForStage("browse to California") {
                scroll.contentOffset.y + scroll.adjustedContentInset.top > 100
            }
            #expect(navigation.selectedRegion == nil)
        }
        let restored = UIHostingController(rootView: LocationsBrowsePane(report: world.report)
            .dynamicTypeSize(.accessibility5).whereBroadwayRoot().bScrollRestorationScope(store))
        try await show(restored) { controller in
            controller.view.frame = CGRect(x: 0, y: 0, width: 466, height: 678)
            controller.view.layoutIfNeeded()
            try await waitForStage("restored California after pane replacement") {
                AdaptivePaneTestSupport.descendants(
                    of: controller.view,
                    matching: UIScrollView.self,
                )
                .contains {
                    $0.contentSize.height > $0.bounds.height && $0.contentOffset.y + $0
                        .adjustedContentInset.top > 100
                }
            }
        }
    }

    @Test func aPushedBrowseStackRemainsMountedThroughTabletop() async throws {
        let world = try await WhereFlyoverWorld.build()
        let navigation = LocationsView.Navigation()
        let state = AdaptivePaneHostState()
        let host = UIHostingController(rootView: AdaptivePaneHostedSurface(state: state) {
            LocationsView(report: world.report, navigation: navigation)
                .environment(world.session).environment(world.model)
        }.bScrollRestorationScope())
        host.safeAreaRegions = []
        @MainActor func controllers(_ root: UIViewController) -> [UIViewController] {
            [root] + root.children.flatMap(controllers)
        }
        try await show(host) { controller in
            controller.view.window?.layer.speed = 1
            try await AdaptivePaneTestSupport.resize(
                controller,
                state: state,
                to: .outerPortrait,
            )
            try await waitForStage("browse stack to mount") {
                controllers(controller).contains { $0 is UINavigationController }
            }
            navigation.open(.flight(PreviewSupport.flightReview(state: .ready)))
            do {
                try await waitForStage("flight detail push") {
                    controllers(controller).compactMap { $0 as? UINavigationController }
                        .contains { $0.viewControllers.count > 1 }
                }
            } catch {
                throw TestHostError(
                    "\(error); path=\(navigation.browsePath.count); controllers=\(controllers(controller).map { String(describing: type(of: $0)) + ":" + (($0 as? UINavigationController)?.navigationBar.topItem?.title ?? $0.title ?? "nil") + ":" + String(($0 as? UINavigationController)?.viewControllers.count ?? 0) })",
                )
            }
            let stack = try #require(controllers(controller)
                .compactMap { $0 as? UINavigationController }
                .first { $0.viewControllers.count > 1 })
            let pushed = try #require(stack.topViewController)
            for pose in [SnapshotConfiguration.Pose.innerPortrait, .tabletop, .outerPortrait] {
                try await AdaptivePaneTestSupport.resize(controller, state: state, to: pose)
                #expect(navigation.browsePath.count == 1)
                #expect(controllers(controller).contains { $0 === pushed })
            }
        }
    }

    private func waitForStage(_ stage: String, _ predicate: () -> Bool) async throws {
        do { try await waitForAsync(predicate: predicate) }
        catch { throw TestHostError("Locations stage: \(stage): \(error)") }
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
        let navigation = LocationsView.Navigation()
        navigation.select(region: .california)
        let state = AdaptivePaneHostState()
        let host = UIHostingController(rootView: AdaptivePaneHostedSurface(state: state) {
            LocationsView(report: report, navigation: navigation)
        })
        host.safeAreaRegions = []
        do {
            try await show(host) { controller in
                let readsBeforeFolding = await store.sampleReadCount
                for pose in [
                    SnapshotConfiguration.Pose.outerPortrait,
                    .innerPortrait,
                    .tabletop,
                    .outerPortrait,
                ] {
                    try await AdaptivePaneTestSupport.resize(controller, state: state, to: pose)
                    #expect(await store.sampleReadCount == readsBeforeFolding)
                    #expect(report.loadState == .loading)
                }
                await report.select(year: 2026)
                let readsAfterYearChange = await store.sampleReadCount
                for pose in [SnapshotConfiguration.Pose.innerLandscape, .tabletop, .outerPortrait] {
                    try await AdaptivePaneTestSupport.resize(controller, state: state, to: pose)
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
