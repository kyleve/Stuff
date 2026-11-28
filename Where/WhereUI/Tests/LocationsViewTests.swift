import AccessibilitySnapshotParser
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
    @Test func openingWithoutARegionShowsAnEmptyDetailUntilSelection() async throws {
        let world = try await WhereFlyoverWorld.build()
        let state = AdaptivePaneHostState()
        let host = UIHostingController(rootView: AdaptivePaneHostedSurface(state: state) {
            LocationsView(report: world.report)
        }.bScrollRestorationScope())
        host.safeAreaRegions = []
        try await show(host) { controller in
            let emptyTitle = String(localized: .locationsNoRegionTitle)
            try await AdaptivePaneTestSupport.resize(controller, state: state, to: .innerPortrait)
            try await waitForStage("empty detail on the open Duo") {
                HostedAccessibility.isVisible(emptyTitle, in: controller.view)
            }
            #expect(HostedAccessibility.isVisible(
                String(localized: .primaryCalendar),
                in: controller.view,
            ) == false)
            #expect(HostedAccessibility.isVisible(
                String(localized: .calendarShowYear),
                in: controller.view,
            ) == false)

            let card = try #require(HostedAccessibility.objects(in: controller.view).first {
                $0.accessibilityLabel?.hasPrefix("California:") == true
                    && $0.accessibilityTraits.contains(.button)
            })
            if let control = card as? UIControl { control.sendActions(for: .touchUpInside) }
            else { try #require(card.accessibilityActivate()) }

            let calendarTitle = WhereFormat.calendarRegionTitle(
                region: .california,
                year: world.report.selectedYear,
            )
            try await waitForStage("selected region calendar") {
                HostedAccessibility.isVisible(calendarTitle, in: controller.view)
            }
            #expect(HostedAccessibility.isVisible(emptyTitle, in: controller.view) == false)

            try await AdaptivePaneTestSupport.resize(controller, state: state, to: .outerPortrait)
            try await waitForStage("selected region calendar stays open when folded") {
                HostedAccessibility.isVisible(calendarTitle, in: controller.view)
                    && HostedAccessibility.isVisible(
                        String(localized: .calendarShowYear),
                        in: controller.view,
                    )
            }
        }
    }

    @Test func estimateCardFollowsVisibleLocationsPanes() async throws {
        let world = try await WhereFlyoverWorld.build()
        let navigation = LocationsView.Navigation()
        navigation.select(region: .california)
        let state = AdaptivePaneHostState()
        let browse = ScrollPositionCapture()
        let calendar = ScrollPositionCapture()
        let host = UIHostingController(rootView: AdaptivePaneHostedSurface(state: state) {
            LocationsView(report: world.report, navigation: navigation)
                .overlay {
                    ScrollPositionProbe(
                        LocationsCardsView.self,
                        role: LocationsCardsView.ScrollRole.browse,
                        context: world.report.selectedYear,
                        idType: Region.self,
                        capture: browse,
                    )
                    ScrollPositionProbe(
                        CalendarContentView.self,
                        role: LocationsView.ScrollRole.calendar,
                        context: CalendarContentView.ScrollContext(
                            region: .california,
                            year: world.report.selectedYear,
                        ),
                        idType: CalendarPresentationState.Target.self,
                        capture: calendar,
                    )
                }
        }.bScrollRestorationScope())
        host.safeAreaRegions = []
        try await show(host) { controller in
            try await AdaptivePaneTestSupport.resize(controller, state: state, to: .outerPortrait)
            try await waitForStage("folded calendar starts at its estimate") {
                guard let target = calendar.binding?.wrappedValue
                    .viewID(type: CalendarPresentationState.Target.self)
                else { return false }
                if case .estimate = target { return true }
                return false
            }
            let estimate = try #require(calendar.binding?.wrappedValue
                .viewID(type: CalendarPresentationState.Target.self))
            try await waitForStage("folded calendar estimate visible") {
                HostedAccessibility.objects(in: controller.view).contains {
                    $0.accessibilityLabel?.hasPrefix("Estimated Time") == true
                        && $0.accessibilityFrame.intersects(controller.view.convert(
                            controller.view.bounds,
                            to: nil,
                        ))
                }
            }
            try await AdaptivePaneTestSupport.resize(controller, state: state, to: .innerLandscape)
            try await waitForStage("secondary calendar starts at a month") {
                guard let target = calendar.binding?.wrappedValue
                    .viewID(type: CalendarPresentationState.Target.self)
                else { return false }
                if case .month = target { return true }
                return false
            }
            let position = try #require(browse.binding)
            position.wrappedValue.scrollTo(edge: .bottom)
            try await waitForStage("primary estimate visible") {
                HostedAccessibility.objects(in: controller.view).contains {
                    $0.accessibilityLabel?.hasPrefix("Estimated Time") == true
                        && $0.accessibilityFrame.intersects(controller.view.convert(
                            controller.view.bounds,
                            to: nil,
                        ))
                }
            }
            #expect(HostedAccessibility.objects(in: controller.view).count(where: {
                $0.accessibilityLabel?.hasPrefix("Estimated Time") == true
            }) == 1)
            #expect(world.report.showsEstimatedTimeAndPlanning)
            try await AdaptivePaneTestSupport.resize(controller, state: state, to: .outerPortrait)
            let detailPosition = try #require(calendar.binding)
            detailPosition.wrappedValue.scrollTo(id: estimate, anchor: .bottom)
            try await waitForStage("calendar estimate available after folding again") {
                HostedAccessibility.objects(in: controller.view).contains {
                    $0.accessibilityLabel?.hasPrefix("Estimated Time") == true
                        && $0.accessibilityFrame.intersects(controller.view.convert(
                            controller.view.bounds,
                            to: nil,
                        ))
                }
            }
        }
    }

    @Test func selectedRegionIsIndicatedOnlyBesideItsCalendar() async throws {
        let world = try await WhereFlyoverWorld.build()
        let navigation = LocationsView.Navigation()
        let state = AdaptivePaneHostState()
        let host = UIHostingController(rootView: AdaptivePaneHostedSurface(state: state) {
            LocationsView(report: world.report, navigation: navigation)
        }.bScrollRestorationScope())
        host.safeAreaRegions = []
        try await show(host) { controller in
            controller.view.window?.layer.speed = 1
            navigation.select(region: .california)
            // Returning to browsing retains the selected region for the next unfold.
            navigation.compactColumn = .sidebar
            for pose in [
                SnapshotConfiguration.DuoPose.outerPortrait,
                .innerLandscape,
                .tabletop,
                .outerPortrait,
            ] {
                try await AdaptivePaneTestSupport.resize(controller, state: state, to: pose)
                try await waitForStage("California card after \(pose)") {
                    HostedAccessibility.objects(in: controller.view).contains {
                        $0.accessibilityLabel?.hasPrefix("California:") == true
                            && $0.accessibilityTraits.contains(.button)
                            && $0.accessibilityFrame.intersects(controller.view.convert(
                                controller.view.bounds,
                                to: nil,
                            ))
                            && $0.accessibilityTraits
                            .contains(.selected) == (pose != .outerPortrait)
                    }
                }
                #expect(navigation.selectedRegion == .california)
            }
        }
    }

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
            @MainActor func currentScroll() -> UIScrollView? {
                AdaptivePaneTestSupport.descendants(
                    of: controller.view,
                    matching: UIScrollView.self,
                )
                .first { $0.window != nil && $0.contentSize.height > $0.bounds.height }
            }
            @MainActor func navigationBarFrame() -> CGRect? {
                AdaptivePaneTestSupport.descendants(
                    of: controller.view,
                    matching: UINavigationBar.self,
                )
                .first { $0.window != nil && $0.bounds.height > 0 }
                .map { $0.convert($0.bounds, to: controller.view) }
            }
            @MainActor func hasAppliedSafeArea(_ scroll: UIScrollView) -> Bool {
                guard let bar = navigationBarFrame() else { return false }
                let viewport = scroll.convert(scroll.bounds, to: controller.view)
                let expectedInset = max(0, bar.maxY - viewport.minY) + scroll.contentInset.top
                return abs(bar.minY - controller.view.safeAreaInsets.top) < 1
                    && abs(scroll.adjustedContentInset.top - expectedInset) < 1
            }
            try await waitForStage("initial navigation and scroll layout") {
                guard let scroll = currentScroll() else { return false }
                return hasAppliedSafeArea(scroll)
                    && abs(scroll.contentOffset.y + scroll.adjustedContentInset.top) < 1
            }
            var scroll = try #require(currentScroll())
            for topInset in [CGFloat(82), 0, 56, 0] {
                let previousInset = scroll.adjustedContentInset.top
                let previousHostInset = controller.view.safeAreaInsets.top
                controller.additionalSafeAreaInsets.top = topInset
                controller.view.setNeedsLayout()
                // Lay out the host whose safe area changed, not only its window.
                controller.view.layoutIfNeeded()
                do {
                    try await waitForStage("host safe area after requested inset \(topInset)") {
                        abs(controller.view.safeAreaInsets.top - previousHostInset) > 1
                    }
                    try await waitForStage(
                        "top anchoring after inset \(previousInset) -> requested \(topInset)",
                    ) {
                        guard let current = currentScroll() else { return false }
                        // The synthetic host's inset change also needs a layout pass in
                        // its embedded navigation controller before child insets converge.
                        var responder: UIResponder? = current
                        while let next = responder, !(next is UIViewController) {
                            responder = next.next
                        }
                        let navigationController = (responder as? UIViewController)?
                            .navigationController
                        navigationController?.view.setNeedsLayout()
                        navigationController?.view.layoutIfNeeded()
                        // Initial navigation layout can change an inset before the requested
                        // safe area reaches the scroll view. Wait for both native frames.
                        return hasAppliedSafeArea(current)
                            && abs(current.adjustedContentInset.top - previousInset) > 1
                            && abs(current.contentOffset.y + current.adjustedContentInset.top) < 1
                    }
                } catch {
                    throw TestHostError(
                        "\(error); requested=\(controller.additionalSafeAreaInsets), hostSafeArea=\(controller.view.safeAreaInsets), bar=\(String(describing: navigationBarFrame())), scrollSafeArea=\(scroll.safeAreaInsets), adjusted=\(scroll.adjustedContentInset), offset=\(scroll.contentOffset), bounds=\(scroll.bounds), content=\(scroll.contentSize), attached=\(scroll.window != nil), current=\(String(describing: currentScroll()))",
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

    @Test func aFlightReviewSheetRemainsMountedAcrossFolds() async throws {
        let world = try await WhereFlyoverWorld.build()
        let report = PreviewSupport.flightYearReportModel(state: .ready)
        _ = try #require(report.liveFlightReview)
        let navigation = LocationsView.Navigation()
        let state = AdaptivePaneHostState()
        let host = UIHostingController(rootView: AdaptivePaneHostedSurface(state: state) {
            LocationsView(report: report, navigation: navigation)
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
            try await waitForStage("flight banner") {
                HostedAccessibility.objects(in: controller.view)
                    .contains {
                        $0.accessibilityHint == String(localized: .flightStatusOpenReview)
                    }
            }
            let banner = try #require(HostedAccessibility.objects(in: controller.view)
                .first {
                    $0.accessibilityHint == String(localized: .flightStatusOpenReview)
                })
            if let control = banner as? UIControl { control.sendActions(for: .touchUpInside) }
            else { try #require(banner.accessibilityActivate()) }
            try await waitForStage("flight review sheet") {
                controller.presentedViewController != nil
            }
            let sheet = try #require(controller.presentedViewController)
            try await waitForStage("flight presentation completes before folding") {
                !sheet.isBeingPresented && sheet.transitionCoordinator == nil
            }
            for pose in [SnapshotConfiguration.DuoPose.innerPortrait, .tabletop, .outerPortrait] {
                try await AdaptivePaneTestSupport.resize(controller, state: state, to: pose)
                #expect(navigation.flightReview != nil)
                #expect(controller.presentedViewController === sheet)
            }
            let done = try #require(HostedAccessibility.objects(in: sheet.view)
                .first { $0.accessibilityLabel == "Done" })
            if let control = done as? UIControl { control.sendActions(for: .touchUpInside) }
            else { try #require(done.accessibilityActivate()) }
            try await waitForStage("return from flight review") {
                controller.presentedViewController == nil
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
                    SnapshotConfiguration.DuoPose.outerPortrait,
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
                for pose in [
                    SnapshotConfiguration.DuoPose.innerLandscape,
                    .tabletop,
                    .outerPortrait,
                ] {
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
