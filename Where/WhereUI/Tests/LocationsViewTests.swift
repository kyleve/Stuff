import SwiftUI
import Testing
@testable import WhereUI

struct LocationsViewTests {
    @Test func screenCompositionKeepsViewValuesWithinStackBudget() {
        #expect(MemoryLayout<LocationsView.Body>.size < 16384)
    }
}
