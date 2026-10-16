import SwiftUI
import TestHostSupport
import Testing
import WhereCore
@_spi(Testing) @testable import WhereUI

@MainActor
struct MainTabsTests {
    @Test func foldingKeepsOnePresentedEditorAndItsUnsavedDate() async throws {
        let world = try await WhereFlyoverWorld.build()
        let navigation = SceneNavigationModel()
        let state = AdaptiveHistoryHostState()
        let host = UIHostingController(rootView: AdaptiveHistoryHostedSurface(state: state) {
            MainTabs(world: world, navigation: navigation)
                .environment(world.model)
                .environment(world.session)
                .environment(\.isInDemoMode, true)
        })
        host.safeAreaRegions = []
        try await show(host) { controller in
            try await AdaptiveHistoryTestSupport.resize(
                controller,
                state: state,
                to: .outerPortrait,
            )
            navigation.locations.select(region: .california)
            let month = CalendarDay(year: world.report.selectedYear, month: 2, day: 1)
            navigation.locations.calendar.reveal(month: month)
            navigation.settings.searchText = "appearance"
            navigation.year.mode = .timeline
            navigation.locations.planningDestination = .new(.california)
            let root = try #require(controller.view.window?.rootViewController)
            try await waitForAsync {
                AdaptiveHistoryTestSupport.presentedController(from: root) != nil
            }
            let editor = try #require(AdaptiveHistoryTestSupport.presentedController(from: root))
            defer { editor.dismiss(animated: false) }
            try await waitForAsync {
                !AdaptiveHistoryTestSupport
                    .descendants(of: editor.view, matching: UIDatePicker.self).isEmpty
            }
            let picker = try #require(AdaptiveHistoryTestSupport.descendants(
                of: editor.view,
                matching: UIDatePicker.self,
            ).first)
            let draft = CalendarDay(year: world.report.selectedYear, month: 9, day: 8)
                .startOfDay(in: world.report.calendar)
            picker.date = draft
            picker.sendActions(for: .valueChanged)
            for pose in [
                AdaptiveHistoryPose.innerPortrait,
                .tabletop,
                .outerPortrait,
                .innerLandscape,
                .outerPortrait,
            ] {
                try await AdaptiveHistoryTestSupport.resize(controller, state: state, to: pose)
                #expect(AdaptiveHistoryTestSupport.presentedController(from: root) === editor)
                #expect(navigation.locations.selectedRegion == .california)
                #expect(navigation.locations.calendar.displayedMonth == month)
                #expect(navigation.settings.searchText == "appearance")
                #expect(navigation.year.mode == .timeline)
                #expect(AdaptiveHistoryTestSupport.descendants(
                    of: editor.view,
                    matching: UIDatePicker.self,
                ).contains {
                    world.report.calendar.isDate($0.date, inSameDayAs: draft)
                })
            }
        }
    }
}
