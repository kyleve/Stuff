import SwiftUI
import Testing
@testable import WhereUI

struct LocationsStateContentTests {
    /// Leave room for repeated SwiftUI graph-update copies on a device's stack.
    @Test func bodyStaysWithinStackBudget() {
        #expect(MemoryLayout<LocationsStateContent.Body>.size < 16384)
    }
}
