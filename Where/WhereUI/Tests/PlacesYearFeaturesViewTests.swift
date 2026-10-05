import SwiftUI
import Testing
@testable import WhereUI

struct PlacesYearFeaturesViewTests {
    /// Leave room for repeated SwiftUI graph-update copies on a device's 1 MB stack.
    @Test func bodyKeepsStoredRowsBehindAViewBoundary() {
        #expect(MemoryLayout<PlacesYearFeaturesView.Body>.size < 16384)
    }
}
