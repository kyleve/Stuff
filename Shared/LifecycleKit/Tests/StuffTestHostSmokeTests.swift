import TestHostSupport
import Testing
import UIKit

@MainActor
struct StuffTestHostSmokeTests {
    @Test func hostProvidesKeyWindowWithRootViewController() {
        let window = hostKeyWindow()
        #expect(window != nil)
        #expect(window?.rootViewController != nil)
    }
}
