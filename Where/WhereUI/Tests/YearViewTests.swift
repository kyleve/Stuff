import AccessibilitySnapshotParser
import BroadwayUI
import SnapshotKit
import SwiftUI
import TestHostSupport
import Testing
@testable import WhereUI

@MainActor
struct YearViewTests {
    @Test func bottomSelectorAndSelectedModeSurviveEveryFoldLayout() async throws {
        let world = try await WhereFlyoverWorld.build()
        let state = AdaptivePaneHostState()
        let host = UIHostingController(rootView: AdaptivePaneHostedSurface(state: state) {
            YearView(report: world.report)
        }.bScrollRestorationScope())
        host.safeAreaRegions = []
        try await show(host) { controller in
            controller.view.window?.layer.speed = 1
            var retainedMode = YearMode.calendar
            for pose in SnapshotConfiguration.Pose.allCases + [.outerPortrait] {
                try await AdaptivePaneTestSupport.resize(controller, state: state, to: pose)
                try await waitForAsync {
                    button(retainedMode, in: controller.view)?.accessibilityTraits
                        .contains(.selected) == true
                }
                for mode in [YearMode.calendar, .timeline] {
                    try await waitForAsync { self.button(mode, in: controller.view) != nil }
                    let button = try #require(self.button(mode, in: controller.view))
                    if let control = button as? UIControl {
                        control.sendActions(for: .touchUpInside)
                    } else {
                        try #require(button.accessibilityActivate())
                    }
                    try await waitForAsync {
                        self.button(mode, in: controller.view)?.accessibilityTraits
                            .contains(.selected) == true
                            && navigationControllers(in: controller)
                            .contains { $0.navigationBar.topItem?.title == mode.title }
                    }
                    #expect(navigationControllers(in: controller).count == 1)
                }
                retainedMode = .timeline
                // Timeline is selected before the next resize; the same view owns it.
                #expect(button(.timeline, in: controller.view)?.accessibilityTraits
                    .contains(.selected) == true)
            }
        }
    }

    private func button(_ mode: YearMode, in view: UIView) -> NSObject? {
        HostedAccessibility.objects(in: view).first {
            $0.accessibilityLabel == mode.title && $0.accessibilityTraits.contains(.button)
                && $0.accessibilityFrame.intersects(view.convert(view.bounds, to: nil))
        }
    }

    private func navigationControllers(in controller: UIViewController)
        -> [UINavigationController]
    {
        (controller as? UINavigationController).map { [$0] } ?? controller.children
            .flatMap { navigationControllers(in: $0) }
    }
}
