import SwiftUI
import TestHostSupport
import Testing
@testable import WhereUI

@MainActor
struct PrivacyPassportCardTests {
    @Test func hosts() throws {
        let rootView = PrivacyPassportCard(presentation: PrivacyPassportPresentation(
            configuration: .defaults(isDebugBuild: false),
        ), settingsReference: .link)
            .whereBroadwayRoot()
        try show(UIHostingController(rootView: rootView)) { hosted in
            #expect(hosted.view != nil)
        }
    }
}
