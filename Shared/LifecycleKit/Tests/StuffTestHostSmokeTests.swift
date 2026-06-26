import Testing
import UIKit
import WhereTesting

@MainActor
struct StuffTestHostSmokeTests {
    @Test func hostProvidesKeyWindowWithRootViewController() {
        let window = hostKeyWindow()
        #expect(window != nil)
        #expect(window?.rootViewController != nil)
    }
}
