import Foundation
@_spi(Testing) import PeriscopeCore
import PeriscopeTools
import SwiftUI
import TestHostSupport
import Testing
import UIKit

@MainActor
struct LogHierarchyViewHostingTests {
    @Test func hostsOverASeededScopeTree() async throws {
        let (store, root, photos, album) = try await makeSeededStore()
        await store.write([
            makeRecord("a", date: date(1), scopes: [root.id]),
            makeRecord("b", date: date(2), scopes: [photos.id]),
            makeRecord("c", date: date(3), scopes: [album.id]),
        ])

        let host = UIHostingController(rootView: NavigationStack {
            LogHierarchyView(store: store)
        })
        try await showHosted(host) { _ in
            #expect(await waitUntil { host.view.window != nil })
        }
    }

    @Test func hostsOverAnEmptyStore() async throws {
        let store = try await PeriscopeStore.inMemory(session: makeSession())

        let host = UIHostingController(rootView: NavigationStack {
            LogHierarchyView(store: store)
        })
        try await showHosted(host) { _ in
            #expect(await waitUntil { host.view.window != nil })
        }
    }
}
