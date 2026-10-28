import SwiftUI
import Testing
@testable import WhereUI

struct RecordingFeaturesViewTests {
    /// Leave room for repeated SwiftUI graph-update copies on a device's 1 MB stack.
    @Test func bodyKeepsStoredRowsBehindAViewBoundary() {
        #expect(MemoryLayout<RecordingFeaturesView.Body>.size < 16384)
    }
}
