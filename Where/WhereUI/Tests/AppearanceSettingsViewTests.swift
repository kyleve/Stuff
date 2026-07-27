import SwiftUI
import TestHostSupport
import Testing
@testable import WhereUI

@MainActor
struct AppearanceSettingsViewTests {
    @Test func hosts() throws {
        let rootView = NavigationStack { AppearanceSettingsView() }
        try show(UIHostingController(rootView: rootView)) { hosted in
            #expect(hosted.view != nil)
        }
    }
}
