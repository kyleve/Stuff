import SwiftUI
import Testing
@testable import WhereUI

struct LocationsStateViewTests {
    /// Leave room for repeated SwiftUI graph-update copies on a device's stack.
    @Test func bodyStaysWithinStackBudget() {
        #expect(MemoryLayout<LocationsStateView.Body>.size < 16384)
    }
}
