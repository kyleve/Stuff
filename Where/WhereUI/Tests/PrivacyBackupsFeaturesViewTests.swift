import SwiftUI
import Testing
@testable import WhereUI

struct PrivacyBackupsFeaturesViewTests {
    /// Leave room for repeated SwiftUI graph-update copies on a device's 1 MB stack.
    @Test func bodyKeepsStoredRowsBehindAViewBoundary() {
        #expect(MemoryLayout<PrivacyBackupsFeaturesView.Body>.size < 16384)
    }
}
