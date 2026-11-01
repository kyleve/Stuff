import InstallerKit
@_spi(Capture) import SnapshotKit
@_spi(Testing) import InstallerKitUI
import SwiftUI
import TestHostSupport
import Testing
import WhereCore
@testable import WhereUI

@MainActor
struct MainTabsTests {
    @Test func halloweenSwitchesTabsAndReturnsFromBackground() async throws {
        let snapshot = try await MainTabs.halloweenSnapshot(selection: .locations)
        guard case let .single(content) = snapshot.capture else {
            Issue.record("Expected the production tab fixture")
            return
        }
        var observedPhase: ScenePhase?
        func root(_ phase: ScenePhase) -> some View {
            content()
                .background { ThemeScenePhaseProbe { observedPhase = $0 } }
                .environment(\.scenePhase, phase)
        }
        let host = UIHostingController(rootView: root(.active))
        try await show(host) { host in
            try await waitForUpdateScene { findTabController(in: host)?.tabs.count == 4 }
            let tabs = try #require(findTabController(in: host))
            for index in [1, 2, 3, 0] {
                tabs.selectedIndex = index
                if let selected = tabs.selectedViewController {
                    tabs.delegate?.tabBarController?(tabs, didSelect: selected)
                }
                try await waitForUpdateScene {
                    tabs.selectedIndex == index && tabs.selectedViewController?.viewIfLoaded?
                        .window != nil
                }
            }
            host.rootView = root(.background)
            try await waitForUpdateScene { observedPhase == .background }
            host.rootView = root(.active)
            try await waitForUpdateScene {
                observedPhase == .active && findTabController(in: host)?.selectedIndex == 0
                    && ThemeInteractionTestSupport.button("California", in: host.view) != nil
            }
            #expect(tabs.tabs.map(\.title) == ["Locations", "Elsewhere", "Your Year", "Settings"])
        }
    }

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
            try await waitForUpdateScene {
                fixture.renderedPhase == .active && updates.needsAttention && !updates.isChecking
            }
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
