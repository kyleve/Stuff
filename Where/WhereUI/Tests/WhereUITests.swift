import SwiftUI
import TestHostSupport
import Testing
import WhereUI

@Test
@MainActor
func rootViewBuilds() throws {
    let vc = UIHostingController(rootView: RootView())
    try show(vc) { hosted in
        #expect(hosted.view != nil)
    }
}
