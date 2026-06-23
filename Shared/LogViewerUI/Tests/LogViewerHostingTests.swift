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
        let rootView = NavigationStack {
            LogViewer(configuration: LogViewerConfiguration(store: store, title: "Logs"))
        }
        try show(UIHostingController(rootView: rootView)) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func viewerHostsWhenEmpty() throws {
        let rootView = NavigationStack {
            LogViewer(configuration: LogViewerConfiguration(store: LogStore(), title: "Logs"))
        }
        try show(UIHostingController(rootView: rootView)) { hosted in
            #expect(hosted.view != nil)
        }
    }
}
