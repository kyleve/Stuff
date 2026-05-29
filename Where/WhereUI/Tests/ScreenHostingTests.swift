import SwiftUI
import Testing
import WhereTesting
@testable import WhereUI

/// Hosts each top-level screen in a real window with seeded preview data to
/// confirm the Liquid Glass layouts mount without crashing.
@MainActor
struct ScreenHostingTests {
    @Test func primaryViewHostsWithData() throws {
        let model = PreviewSupport.loadedModel()
        try show(UIHostingController(rootView: PrimaryView().environment(model))) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func secondaryViewHostsWithData() throws {
        let model = PreviewSupport.loadedModel()
        try show(UIHostingController(rootView: SecondaryView().environment(model))) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func settingsViewHosts() throws {
        let model = PreviewSupport.loadedModel()
        try show(UIHostingController(rootView: SettingsView().environment(model))) { hosted in
            #expect(hosted.view != nil)
        }
    }
}
