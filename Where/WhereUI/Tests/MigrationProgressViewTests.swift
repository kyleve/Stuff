import LifecycleKit
import SwiftUI
import Testing
import WhereTesting
import WhereUI

@MainActor
struct MigrationProgressViewTests {
    @Test func indeterminateRenders() throws {
        let view = MigrationProgressView(bridge: LifecycleStepUIBridge(reason: .userForeground))
        try show(UIHostingController(rootView: view)) { hosted in
            waitForOneRunloop()
            #expect(hosted.view != nil)
        }
    }

    @Test func determinateWithMessageRenders() throws {
        let bridge = LifecycleStepUIBridge(reason: .userForeground)
        bridge.progress = 0.5
        bridge.message = "Migrating manual days…"
        let view = MigrationProgressView(bridge: bridge)
        try show(UIHostingController(rootView: view)) { hosted in
            waitForOneRunloop()
            #expect(hosted.view != nil)
        }
    }
}
