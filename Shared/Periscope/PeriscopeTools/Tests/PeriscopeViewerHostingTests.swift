import Foundation
@_spi(Testing) import PeriscopeCore
import PeriscopeTools
import SwiftUI
import Testing
import UIKit
import WhereTesting

/// Drives in-place input swaps for rebinding tests.
@MainActor
@Observable
private final class StoreHolder {
    var store: PeriscopeStore

    init(store: PeriscopeStore) {
        self.store = store
    }
}

private struct SwappingHost: View {
    let holder: StoreHolder

    var body: some View {
        NavigationStack {
            PeriscopeViewer(store: holder.store, title: "Logs")
        }
    }
}

@MainActor
struct PeriscopeViewerHostingTests {
    @Test func swappingTheStoreInPlaceRebindsTheViewer() async throws {
        let (storeA, _, _, _) = try await makeSeededStore()
        let storeB = try await PeriscopeStore.inMemory(session: makeSession())
        let holder = StoreHolder(store: storeA)

        let host = UIHostingController(rootView: SwappingHost(holder: holder))
        try await showHosted(host) { _ in
            let boundToA = await waitUntil {
                await storeA.changeObserverCount == 1
            }
            #expect(boundToA)

            holder.store = storeB

            // The re-keyed task rebinds to B and cancelling the old task
            // releases A's stream — State(initialValue:) alone would leave
            // the viewer pinned to A.
            let boundToB = await waitUntil {
                await storeB.changeObserverCount == 1
            }
            #expect(boundToB)
            let releasedA = await waitUntil {
                await storeA.changeObserverCount == 0
            }
            #expect(releasedA)
        }
    }

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
