import InstallerKit
@_spi(Testing) import InstallerKitUI
import SwiftUI
import TestHostSupport
import Testing
import WhereCore
@testable import WhereUI

@MainActor
struct MainTabsTests {
    @Test func elsewhereTabAppearsForAVisitAndFallsBackAfterItsRemoval() async throws {
        let session = PreviewSupport.loadedSession()
        session.preferences.showsLocationWelcome = false
        let root = MainTabs(
            session: session,
            initialDetails: nil,
            selectedYear: PreviewSupport.year,
        )
        .environment(session)
        .environment(PreviewSupport.loadedModel())
        .environment(\.scenePhase, .active)
        .whereBroadwayRoot()
        try await show(UIHostingController(rootView: root)) { host in
            try await waitForUpdateScene { findTabController(in: host)?.tabs.count == 3 }
            let tabs = try #require(findTabController(in: host))
            let date = PreviewSupport.referenceNow
            try await session.services.journal.addManualDay(
                date: date,
                regions: [.other],
                audit: nil,
            )
            try await waitForUpdateScene { tabs.tabs.count == 4 }
            #expect(tabs.tabs.map(\.title) == ["Locations", "Elsewhere", "Your Year", "Settings"])
            tabs.selectedIndex = 1
            if let selected = tabs.selectedViewController {
                tabs.delegate?.tabBarController?(tabs, didSelect: selected)
            }
            try await session.services.journal.addManualDay(
                date: date,
                regions: [.california],
                audit: nil,
            )
            try await waitForUpdateScene { tabs.tabs.count == 3 && tabs.selectedIndex == 0 }
            #expect(tabs.tabs.map(\.title) == ["Locations", "Your Year", "Settings"])
        }
    }

    @Test func checksWhenTheSceneEntersAndReturnsToTheForeground() async throws {
        let session = PreviewSupport.loadedSession()
        session.preferences.showsLocationWelcome = false
        let fixture = UpdateSceneFixture()
        let client = UpdateSceneClient(InstallerPreview.catalog(.available))
        let updates = UpdateModel(service: UpdateService(
            installed: InstallerPreview.distribution(),
            preferences: WherePreferences(store: InMemoryKeyValueStore()),
            client: client,
            now: { fixture.now },
        ))
        let root = UpdateSceneHost(fixture: fixture, session: session, updates: updates)
        try await show(UIHostingController(rootView: root)) { _ in
            try await waitForUpdateScene { fixture.renderedPhase == .background }
            #expect(client.fetchCount == 0)
            fixture.phase = .active
            try await waitForUpdateScene { updates.needsAttention }
            #expect(client.fetchCount == 1)
            fixture.phase = .background
            try await waitForUpdateScene { fixture.renderedPhase == .background }
            fixture.now = fixture.now.addingTimeInterval(3600)
            fixture.phase = .active
            try await waitForUpdateScene { client.fetchCount == 2 && !updates.isChecking }
            #expect(updates.needsAttention)
        }
    }
}

@MainActor
struct MainTabsTestsDuo {
    @Test func settingsSearchStaysVisibleAcrossFoldLayouts() async throws {
        let world = try await WhereFlyoverWorld.build()
        let navigation = SceneNavigationModel()
        navigation.selectedTab = .settings
        let state = AdaptiveHistoryHostState()
        let host = UIHostingController(rootView: AdaptiveHistoryHostedSurface(state: state) {
            MainTabs(world: world, navigation: navigation)
                .environment(world.model)
                .environment(world.session)
                .environment(\.isInDemoMode, true)
        })
        host.safeAreaRegions = []
        try await show(host) { controller in
            for pose in [
                AdaptiveHistoryPose.outerPortrait,
                .innerPortrait,
                .tabletop,
                .book,
                .outerPortrait,
            ] {
                try await AdaptiveHistoryTestSupport.resize(controller, state: state, to: pose)
                let window = try #require(controller.view.window)
                try await waitForAsync {
                    AdaptiveHistoryTestSupport.descendants(
                        of: window,
                        matching: UISearchTextField.self,
                    )
                    .contains { field in
                        var ancestor: UIView? = field
                        while let view = ancestor {
                            if view.isHidden || view.alpha == 0 { return false }
                            ancestor = view.superview
                        }
                        let frame = field.convert(field.bounds, to: controller.view)
                        return frame.width > 0 && frame.height > 0 && controller.view.bounds
                            .contains(frame)
                    }
                }
            }
        }
    }

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
