import AccessibilitySnapshotParser
import BroadwayUI
import RegionKit
import SnapshotKit
import SwiftUI
import TestHostSupport
import Testing
import WhereCore
@testable import WhereUI

@MainActor
struct LocationsSplitInteractionTests {
    @Test func expandedIndexStaysVisibleAcrossFolds() async throws {
        let report = PreviewSupport.loadedYearReportModel()
        let navigation = LocationsView.Navigation()
        let state = AdaptivePaneHostState()
        let host = UIHostingController(rootView: AdaptivePaneHostedSurface(state: state) {
            LocationsView(report: report, navigation: navigation)
        }.bScrollRestorationScope())
        host.safeAreaRegions = []
        func controllers(_ root: UIViewController) -> [UIViewController] {
            [root] + root.children.flatMap(controllers)
        }
        try await show(host) { _ in
            let controller = host
            for pose in [
                SnapshotConfiguration.DuoPose.outerPortrait,
                .innerPortrait,
                .tabletop,
                .outerPortrait,
            ] {
                try await AdaptivePaneTestSupport.resize(controller, state: state, to: pose)
                let split = try #require(controllers(controller)
                    .compactMap { $0 as? UISplitViewController }.first)
                if pose == .innerPortrait || pose == .tabletop {
                    do {
                        try await waitForAsync {
                            !split.isCollapsed && split.displayMode == .oneBesideSecondary
                                && !split.presentsWithGesture && split
                                .displayModeButtonVisibility == .never
                        }
                    } catch {
                        throw TestHostError(
                            "Expanded split at \(pose): collapsed=\(split.isCollapsed), gesture=\(split.presentsWithGesture), button=\(split.displayModeButtonVisibility.rawValue), mode=\(split.displayMode.rawValue)",
                        )
                    }
                } else {
                    try await waitForAsync { split.isCollapsed }
                }
                navigation.select(region: .california)
                try await waitForAsync {
                    HostedAccessibility.objects(in: controller.view).contains {
                        $0.accessibilityLabel == "Show Year"
                    }
                }
            }
        }
    }
}
