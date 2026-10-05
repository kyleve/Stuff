import SwiftUI
import Testing
@testable import WhereUI

struct PersonalizationFeaturesViewTests {
    /// Leave room for repeated SwiftUI graph-update copies on a device's 1 MB stack.
    @Test func bodyKeepsTheFormBehindAViewBoundary() {
        #expect(MemoryLayout<PersonalizationFeaturesView.Body>.size < 16384)
    }
}
