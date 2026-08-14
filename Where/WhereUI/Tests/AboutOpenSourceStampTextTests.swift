import SwiftUI
import TestHostSupport
import Testing
@testable import WhereUI

@MainActor
struct AboutOpenSourceStampTextTests {
    @Test func hosts() throws {
        let rootView = AboutOpenSourceStampText().whereBroadwayRoot()
        try show(UIHostingController(rootView: rootView)) { hosted in
            #expect(hosted.view != nil)
        }
    }
}
