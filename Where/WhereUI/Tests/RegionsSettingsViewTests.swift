import SwiftUI
import TestHostSupport
import Testing
@testable import WhereUI

@MainActor
struct RegionsSettingsViewTests {
    /// Presented as a sheet, so it owns its own navigation stack.
    @Test func hostsWithASession() throws {
        let rootView = RegionsSettingsView()
            .environment(PreviewSupport.loadedSession())
        try show(UIHostingController(rootView: rootView)) { hosted in
            #expect(hosted.view != nil)
        }
    }
}
