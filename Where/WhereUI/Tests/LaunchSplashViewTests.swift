import SwiftUI
import TestHostSupport
import Testing
@testable import WhereUI

@MainActor
struct LaunchSplashViewTests {
    @Test func splashRenders() throws {
        let view = LaunchSplashView(previewImageName: "AppIconClassic")
        try show(UIHostingController(rootView: view)) { hosted in
            waitForOneRunloop()
            #expect(hosted.view != nil)
        }
    }

    @Test func splashWithSlowLaunchCaptionRenders() throws {
        let view = LaunchSplashView(previewImageName: "AppIconClassic", previewShowsCaption: true)
        try show(UIHostingController(rootView: view)) { hosted in
            waitForOneRunloop()
            #expect(hosted.view != nil)
        }
    }

    /// The first-run variant (`showsDataCaption: false` — no data to update,
    /// so the "Updating your data…" caption never arms) still renders.
    @Test func firstRunSplashWithoutDataCaptionRenders() throws {
        let view = LaunchSplashView(showsDataCaption: false, previewImageName: "AppIconClassic")
        try show(UIHostingController(rootView: view)) { hosted in
            waitForOneRunloop()
            #expect(hosted.view != nil)
        }
    }
}
