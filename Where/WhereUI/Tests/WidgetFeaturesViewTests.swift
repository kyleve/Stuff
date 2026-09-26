import SwiftUI
import Testing
@testable import WhereUI

struct WidgetFeaturesViewTests {
    /// Leave room for repeated SwiftUI graph-update copies on a device's 1 MB stack.
    @Test func bodyKeepsTheFormBehindAViewBoundary() {
        #expect(MemoryLayout<WidgetFeaturesView.Body>.size < 16384)
    }
}
