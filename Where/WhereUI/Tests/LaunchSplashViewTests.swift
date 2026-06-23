import SwiftUI
import Testing
import WhereTesting
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
}
