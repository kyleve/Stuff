import LogKit
import LogViewerUI
import SwiftUI
import Testing
import WhereTesting

@MainActor
struct LogViewerHostingTests {
    @Test func viewerHostsWithEntries() throws {
        let store = LogStore()
        store.record(LogEntry(level: .error, subsystem: "s", category: "DB", message: "boom"))
        #expect(store.snapshot().map(\.message) == ["boom"])

        let rootView = NavigationStack {
            LogViewer(configuration: LogViewerConfiguration(store: store, title: "Logs"))
        }
        try show(UIHostingController(rootView: rootView)) { hosted in
            waitForOneRunloop()
            hosted.view.layoutIfNeeded()
            #expect(hosted.parent != nil)
            #expect(hosted.view.window != nil)
            #expect(hosted.view.bounds.width > 0)
            #expect(hosted.view.bounds.height > 0)
        }
    }

    @Test func viewerHostsWhenEmpty() throws {
        let store = LogStore()
        #expect(store.snapshot().isEmpty)

        let rootView = NavigationStack {
            LogViewer(configuration: LogViewerConfiguration(store: store, title: "Logs"))
        }
        try show(UIHostingController(rootView: rootView)) { hosted in
            waitForOneRunloop()
            hosted.view.layoutIfNeeded()
            #expect(hosted.parent != nil)
            #expect(hosted.view.window != nil)
            #expect(hosted.view.bounds.width > 0)
            #expect(hosted.view.bounds.height > 0)
        }
    }
}
