import LifecycleKit
import SwiftUI
import Testing
import WhereTesting
import WhereUI

@MainActor
struct MigrationProgressViewTests {
    @Test func indeterminateRenders() throws {
        let view = MigrationProgressView(handle: StepHandle(reason: .userForeground))
        try show(UIHostingController(rootView: view)) { hosted in
            waitForOneRunloop()
            #expect(hosted.view != nil)
        }
    }

    @Test func determinateWithMessageRenders() throws {
        let handle = StepHandle(reason: .userForeground)
        handle.progress = 0.5
        handle.message = "Migrating manual days…"
        let view = MigrationProgressView(handle: handle)
        try show(UIHostingController(rootView: view)) { hosted in
            waitForOneRunloop()
            #expect(hosted.view != nil)
        }
    }
}
