import SwiftUI
import Testing
@testable import WhereUI

struct ShareEvidenceFeaturesViewTests {
    /// Leave room for repeated SwiftUI graph-update copies on a device's 1 MB stack.
    @Test func bodyKeepsTheFormBehindAViewBoundary() {
        #expect(MemoryLayout<ShareEvidenceFeaturesView.Body>.size < 16384)
    }
}
