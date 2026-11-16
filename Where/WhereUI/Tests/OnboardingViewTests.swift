import LifecycleKit
import SwiftUI
import TestHostSupport
import Testing
@_spi(Testing) import WhereCore
@testable import WhereUI

@MainActor
@Suite(.serialized)
struct OnboardingViewTests {
    @Test func landscapeIntroKeepsLargeTextReachableAboveTheFooter() async throws {
        let host = UIHostingController(rootView: OnboardingView(
            gate: LifecycleGateHandle(id: LaunchStepID.onboarding, reason: .userForeground),
            installationContext: .testing,
        )
        .environment(PreviewSupport.onboardingModel())
        .whereBroadwayRoot())
        host.safeAreaRegions = []
        host.traitOverrides.horizontalSizeClass = .regular
        host.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge

        try await show(host) { controller in
            controller.view.frame = CGRect(x: 0, y: 0, width: 1194, height: 834)
            controller.view.layoutIfNeeded()
            let continueTitle = String(localized: .onboardingContinue)
            try await waitForAsync { element(continueTitle, in: controller.view) != nil }
            let viewport = controller.view.convert(controller.view.bounds, to: nil)
            let footer = try #require(element(continueTitle, in: controller.view))
            let footerFrame = footer.accessibilityFrame
            #expect(viewport.contains(footerFrame))
            for label in [
                String(localized: .onboardingRestoreBackup),
                String(localized: .onboardingTryDemo),
            ] {
                #expect(try viewport
                    .contains(#require(element(label, in: controller.view)).accessibilityFrame))
            }

            let scroll = try #require(AdaptivePaneTestSupport.descendants(
                of: controller.view,
                matching: UIScrollView.self,
            ).first {
                $0.contentSize.height > $0.bounds.height + 1 &&
                    $0.convert($0.bounds, to: controller.view).intersects(controller.view.bounds)
            })
            #expect(abs(scroll.bounds.width - viewport.width) < 1)
            scroll.setContentOffset(
                CGPoint(x: 0, y: scroll.contentSize.height - scroll.bounds.height),
                animated: false,
            )
            controller.view.layoutIfNeeded()
            let description = try #require(element(
                OnboardingPage.all[0].description,
                in: controller.view,
            ))
            let pageFrame = scroll.convert(scroll.bounds, to: nil)
            #expect(pageFrame.contains(CGPoint(
                x: description.accessibilityFrame.midX,
                y: description.accessibilityFrame.maxY - 1,
            )))
            #expect(description.accessibilityFrame.maxY < footerFrame.minY)
            let indicator = try #require(AdaptivePaneTestSupport.descendants(
                of: controller.view,
                matching: UIPageControl.self,
            ).first)
            #expect(description.accessibilityFrame.maxY <= indicator.convert(
                indicator.bounds,
                to: nil,
            ).minY)
            #expect(element(continueTitle, in: controller.view)?.accessibilityFrame == footerFrame)
        }
    }

    private func element(_ label: String, in view: UIView) -> NSObject? {
        HostedAccessibility.objects(in: view).first { $0.accessibilityLabel == label }
    }
}
