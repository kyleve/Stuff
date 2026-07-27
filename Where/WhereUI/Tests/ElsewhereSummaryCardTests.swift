import SwiftUI
import TestHostSupport
import Testing
@testable import WhereUI

@MainActor
struct ElsewhereSummaryCardTests {
    @Test func hosts() throws {
        try show(UIHostingController(rootView: ElsewhereSummaryCard(regionCount: 3))) { hosted in
            #expect(hosted.view != nil)
        }
    }
}
