import SwiftUI
import Testing
@testable import WhereUI

struct LocationsCardsViewTests {
    /// Leave room for repeated SwiftUI graph-update copies on a device's stack.
    @Test func bodyStaysWithinStackBudget() {
        #expect(MemoryLayout<LocationsCardsView.Body>.size < 16384)
    }
}
