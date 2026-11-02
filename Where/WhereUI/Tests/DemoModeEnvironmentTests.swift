import SwiftUI
import Testing
import WhereUI

@MainActor
struct DemoModeEnvironmentTests {
    @Test func defaultsToTheRealAppOutsideAnyInjection() {
        // The safer default: a view rendered outside the app root (a preview, a
        // widget) reads as the real app, so demo-only affordances stay hidden
        // rather than appearing where there is no demo to leave.
        #expect(!EnvironmentValues().isInDemoMode)
    }
}
