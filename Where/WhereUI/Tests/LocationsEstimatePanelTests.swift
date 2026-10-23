import SwiftUI
import Testing
@testable import WhereUI

struct LocationsEstimatePanelTests {
    /// Leave room for repeated SwiftUI graph-update copies on a device's stack.
    @Test func bodyStaysWithinStackBudget() {
        #expect(MemoryLayout<LocationsEstimatePanel.Body>.size < 16384)
    }
}
