import SwiftUI
import TestHostSupport
import Testing
@testable import WhereUI

@MainActor
struct ElsewhereSummaryCardTests {
    @Test func hosts() throws {
        try show(UIHostingController(rootView: ElsewhereSummaryCard(regions: [
            .canada,
            .europeanUnion,
            .other,
        ]))) { hosted in
            #expect(hosted.view != nil)
        }
    }
}
