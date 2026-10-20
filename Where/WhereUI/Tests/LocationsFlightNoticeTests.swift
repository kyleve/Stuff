import SwiftUI
import Testing
@testable import WhereUI

struct LocationsFlightNoticeTests {
    /// Leave room for repeated SwiftUI graph-update copies on a device's stack.
    @Test func bodyStaysWithinStackBudget() {
        #expect(MemoryLayout<LocationsFlightNotice.Body>.size < 16384)
    }
}
