import SwiftUI
import Testing
@testable import WhereUI

struct FeatureGuidePageTests {
    @Test func pageScopesKeepTheFormBehindAViewBoundary() {
        #expect(MemoryLayout<FeatureGuidePage<Text>.Body>.size < 16384)
    }
}
