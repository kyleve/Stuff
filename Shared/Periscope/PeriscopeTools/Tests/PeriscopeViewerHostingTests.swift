import Foundation
@_spi(Testing) import PeriscopeCore
import PeriscopeTools
import SwiftUI
import Testing
import UIKit
import WhereTesting

@MainActor
struct PeriscopeViewerHostingTests {
    @Test func viewerHostsOverASeededStore() async throws {
        let (store, root, _, _) = try await makeSeededStore()
        await store.write([
            makeRecord("hello viewer", date: date(1), scopes: [root.id]),
        ])

        let host = UIHostingController(rootView: NavigationStack {
            PeriscopeViewer(store: store, title: "Logs")
        })
        try show(host) { _ in
            try waitFor { host.view.window != nil }
        }
    }

    @Test func viewerHostsOverAnEmptyStore() async throws {
        let store = try await PeriscopeStore.inMemory(session: makeSession())

        let host = UIHostingController(rootView: NavigationStack {
            PeriscopeViewer(store: store, title: "Logs")
        })
        try show(host) { _ in
            try waitFor { host.view.window != nil }
        }
    }
}
