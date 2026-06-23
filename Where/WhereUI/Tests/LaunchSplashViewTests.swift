import LifecycleKit
import SwiftUI
import Testing
import WhereTesting
@testable import WhereUI

@MainActor
struct LaunchSplashViewTests {
    @Test func idleSplashRendersWithoutABridge() throws {
        let view = LaunchSplashView(previewImageName: "AppIconClassic")
        try show(UIHostingController(rootView: view)) { hosted in
            waitForOneRunloop()
            #expect(hosted.view != nil)
        }
    }

    @Test func indeterminateMigrationCaptionRenders() throws {
        let view = LaunchSplashView(
            previewImageName: "AppIconClassic",
            bridge: LifecycleStepUIBridge(reason: .userForeground),
        )
        try show(UIHostingController(rootView: view)) { hosted in
            waitForOneRunloop()
            #expect(hosted.view != nil)
        }
    }

    @Test func determinateMigrationCaptionRenders() throws {
        let bridge = LifecycleStepUIBridge(reason: .userForeground)
        bridge.progress = 0.5
        bridge.message = "Migrating manual days…"
        let view = LaunchSplashView(previewImageName: "AppIconClassic", bridge: bridge)
        try show(UIHostingController(rootView: view)) { hosted in
            waitForOneRunloop()
            #expect(hosted.view != nil)
        }
    }
}
