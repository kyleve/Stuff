@_spi(Testing) import LogKit
import LogViewerUI
import SwiftUI
import TestHostSupport
import Testing
import UIKit

private func isViewHosted(_ hosted: UIViewController) -> Bool {
    hosted.parent != nil
        && hosted.view.window != nil
        && hosted.view.bounds.width > 0
        && hosted.view.bounds.height > 0
}

@MainActor
struct LogViewerHostingTests {
    @Test func viewerHostsWithEntries() throws {
        let store = LogStore()
        store.record(LogEntry(level: .error, subsystem: "s", category: "DB", message: "boom"))
        #expect(store.snapshot().map(\.message) == ["boom"])

        let rootView = NavigationStack {
            LogViewer(configuration: LogViewerConfiguration(store: store, title: "Logs"))
        }
        let hosted = UIHostingController(rootView: rootView)
        try show(hosted) { controller in
            try waitFor { isViewHosted(controller) }
        }
    }

    @Test func viewerHostsWhenEmpty() throws {
        let store = LogStore()
        #expect(store.snapshot().isEmpty)

        let rootView = NavigationStack {
            LogViewer(configuration: LogViewerConfiguration(store: store, title: "Logs"))
        }
        let hosted = UIHostingController(rootView: rootView)
        try show(hosted) { controller in
            try waitFor { isViewHosted(controller) }
        }
    }

    @Test func viewerHostsWithMultipleStores() throws {
        // Mirrors the Settings entry, which merges WhereLog + RegionLog buffers.
        let appStore = LogStore()
        appStore.record(LogEntry(
            level: .info,
            subsystem: "app",
            category: "Session",
            message: "hi",
        ))
        let regionStore = LogStore()
        regionStore.record(LogEntry(
            level: .error,
            subsystem: "region",
            category: "RegionAttributor",
            message: "boom",
        ))

        let rootView = NavigationStack {
            LogViewer(configuration: LogViewerConfiguration(
                stores: [appStore, regionStore],
                title: "Logs",
            ))
        }
        let hosted = UIHostingController(rootView: rootView)
        try show(hosted) { controller in
            try waitFor { isViewHosted(controller) }
        }
    }
}
