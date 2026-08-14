import SwiftUI
import TestHostSupport
import Testing
@testable import WhereUI

@MainActor
struct PrivacyPassportHeaderTests {
    @Test func hosts() throws {
        let rootView = PrivacyPassportHeader().whereBroadwayRoot()
        try show(UIHostingController(rootView: rootView)) { hosted in
            #expect(hosted.view != nil)
        }
    }
}
