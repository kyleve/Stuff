import SwiftUI
import TestHostSupport
import Testing
@testable import WhereUI

@MainActor
struct PrivacyPassportDisclosureRowTests {
    @Test func hosts() throws {
        let rootView = PrivacyPassportDisclosureRow(disclosure: .crashReports)
            .whereBroadwayRoot()
        try show(UIHostingController(rootView: rootView)) { hosted in
            #expect(hosted.view != nil)
        }
    }
}
