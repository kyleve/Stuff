import BroadwayUI
import InstallerKit
import RegionKit
import SnapshotKit
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
        let report = YearReportModel(
            services: session.services,
            selectedYear: PreviewSupport.year,
            preferences: session.preferences,
            now: session.now,
        )
        var elsewheres: [ElsewhereModel] = []
        let root = MainTabs(
            session: session,
            report: report,
            welcome: LocationWelcomeModel(
                services: session.services,
                preferences: session.preferences,
                now: session.now,
            ),
            selection: .locations,
            makeElsewhere: {
                let model = ElsewhereModel(
                    resolver: session.services.elsewhere,
                    namer: PreviewPlaceNamer(),
                )
                elsewheres.append(model)
                return model
            },
        )
        .environment(session)
        .environment(PreviewSupport.loadedModel())
        .environment(\.scenePhase, .active)
        .whereBroadwayRoot()
        let controller: UIViewController = UIHostingController(rootView: root)
        try await TestHostSupport.show(controller) { (_: UIViewController) async throws in
            try await waitForUpdateScene { findTabController(in: controller)?.tabs.count == 3 }
            #expect(elsewheres.isEmpty)
            let tabs = try #require(findTabController(in: controller))
            let date = PreviewSupport.referenceNow
            let nevada = try #require(Region(rawValue: "us-NV"))
            try await session.services.journal.addManualDay(
                date: date,
                regions: [nevada],
                audit: nil,
            )
            try await waitForUpdateScene { tabs.tabs.count == 4 }
            #expect(tabs.tabs.map(\.title) == ["Locations", "Elsewhere", "Your Year", "Settings"])
            tabs.selectedIndex = 1
            if let selected = tabs.selectedViewController {
                tabs.delegate?.tabBarController?(tabs, didSelect: selected)
            }
            try await waitForUpdateScene { elsewheres.count == 1 }
            try await waitForUpdateScene {
                elsewheres.first?.content(for: report.selectedYear) != nil
            }
            try await waitForUpdateScene("the Nevada card") {
                HostedAccessibility.objects(in: controller.view).contains {
                    $0.accessibilityLabel?.hasPrefix("\(nevada.localizedName):") == true
                }
            }
            let card = try #require(HostedAccessibility.objects(in: controller.view).first {
                $0.accessibilityLabel?.hasPrefix("\(nevada.localizedName):") == true
            })
            if let control = card as? UIControl { control.sendActions(for: .touchUpInside) }
            else { try #require(card.accessibilityActivate()) }
            let detailIsVisible: @MainActor () -> Bool = {
                HostedAccessibility.isVisible(nevada.localizedName, in: controller.view)
            }
            try await waitForUpdateScene("the region detail") { detailIsVisible() }
            let secondDate = try #require(report.calendar.date(byAdding: .day, value: -1, to: date))
            try await session.services.journal.addManualDay(
                date: secondDate,
                regions: [nevada],
                audit: nil,
            )
            try await waitForUpdateScene("the shared two-day projection in the region detail") {
                elsewheres.first?.content(for: report.selectedYear)?
                    .regions.first?.days.count == 2 && detailIsVisible()
            }
            #expect(elsewheres.count == 1)
            try await session.services.journal.addManualDay(
                date: secondDate,
                regions: [.california],
                audit: nil,
            )
            try await session.services.journal.addManualDay(
                date: date,
                regions: [.california],
                audit: nil,
            )
            try await waitForUpdateScene { tabs.tabs.count == 3 && tabs.selectedIndex == 0 }
            #expect(tabs.tabs.map(\.title) == ["Locations", "Your Year", "Settings"])
            try await session.services.journal.addManualDay(
                date: date,
                regions: [.other],
                audit: nil,
            )
            try await waitForUpdateScene { tabs.tabs.count == 4 }
            tabs.selectedIndex = 1
            if let selected = tabs.selectedViewController {
                tabs.delegate?.tabBarController?(tabs, didSelect: selected)
            }
            try await waitForUpdateScene { elsewheres.count == 2 }
            #expect(elsewheres[0] !== elsewheres[1])
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
        let state = AdaptivePaneHostState()
        let host = UIHostingController(rootView: AdaptivePaneHostedSurface(state: state) {
            MainTabs(world: world, tab: .settings)
                .environment(world.model)
                .environment(world.session)
                .environment(\.isInDemoMode, true)
        })
        host.safeAreaRegions = []
        try await show(host) { controller in
            var enteredQuery = false
            for pose in [
                SnapshotConfiguration.DuoPose.outerPortrait,
                .innerPortrait,
                .tabletop,
                .book,
                .outerPortrait,
            ] {
                try await AdaptivePaneTestSupport.resize(controller, state: state, to: pose)
                let window = try #require(controller.view.window)
                try await waitForAsync {
                    AdaptivePaneTestSupport.descendants(
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
                let field = try #require(AdaptivePaneTestSupport.descendants(
                    of: window,
                    matching: UISearchTextField.self,
                ).first { !$0.isHidden && $0.window != nil })
                if !enteredQuery {
                    field.text = "appearance"
                    field.sendActions(for: .editingChanged)
                    enteredQuery = true
                }
                #expect(field.text == "appearance")
            }
        }
    }

    @Test func foldingKeepsOnePresentedEditorAndItsUnsavedDate() async throws {
        let world = try await WhereFlyoverWorld.build()
        let navigation = LocationsView.Navigation()
        let state = AdaptivePaneHostState()
        let host = UIHostingController(rootView: AdaptivePaneHostedSurface(state: state) {
            LocationsView(report: world.report, navigation: navigation)
                .bScrollRestorationScope()
                .environment(world.model)
                .environment(world.session)
                .environment(\.isInDemoMode, true)
        })
        host.safeAreaRegions = []
        try await show(host) { controller in
            try await AdaptivePaneTestSupport.resize(
                controller,
                state: state,
                to: .outerPortrait,
            )
            navigation.select(region: .california)
            navigation.planningDestination = .new(.california)
            let root = try #require(controller.view.window?.rootViewController)
            try await waitForAsync {
                AdaptivePaneTestSupport.presentedController(from: root) != nil
            }
            let editor = try #require(AdaptivePaneTestSupport.presentedController(from: root))
            defer { editor.dismiss(animated: false) }
            // A picker can exist before native presentation finishes. Fold the mounted editor
            // after that transition, rather than forcing layout during sheet installation.
            try await waitForAsync {
                !editor.isBeingPresented && editor.transitionCoordinator == nil
                    && !AdaptivePaneTestSupport
                    .descendants(of: editor.view, matching: UIDatePicker.self).isEmpty
            }
            let picker = try #require(AdaptivePaneTestSupport.descendants(
                of: editor.view,
                matching: UIDatePicker.self,
            ).first)
            let draft = CalendarDay(year: world.report.selectedYear, month: 9, day: 8)
                .startOfDay(in: world.report.calendar)
            picker.date = draft
            picker.sendActions(for: .valueChanged)
            for pose in [
                SnapshotConfiguration.DuoPose.innerPortrait,
                .tabletop,
                .outerPortrait,
                .innerLandscape,
                .outerPortrait,
            ] {
                try await AdaptivePaneTestSupport.resize(controller, state: state, to: pose)
                #expect(AdaptivePaneTestSupport.presentedController(from: root) === editor)
                #expect(navigation.selectedRegion == .california)
                #expect(AdaptivePaneTestSupport.descendants(
                    of: editor.view,
                    matching: UIDatePicker.self,
                ).contains {
                    world.report.calendar.isDate($0.date, inSameDayAs: draft)
                })
            }
        }
    }
}
