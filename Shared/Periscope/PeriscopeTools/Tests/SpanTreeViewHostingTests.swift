import Foundation
@_spi(Testing) import PeriscopeCore
import PeriscopeTools
import SwiftUI
import TestHostSupport
import Testing
import UIKit

@MainActor
struct SpanTreeViewHostingTests {
    @Test func hostsOverRecordedSpans() async throws {
        let (store, root, _, _) = try await makeSeededStore()
        let outer = SpanID()
        let inner = SpanID()
        await store.write([
            spanBegan(outer, name: "outer", at: date(0), scope: root.id),
            spanBegan(inner, name: "inner", at: date(1), scope: root.id),
            spanEnded(inner, name: "inner", at: date(2), duration: .seconds(1), scope: root.id),
            spanEnded(outer, name: "outer", at: date(3), duration: .seconds(3), scope: root.id),
        ])

        let host = UIHostingController(rootView: NavigationStack {
            SpanTreeView(store: store)
        })
        try await showHosted(host) { _ in
            #expect(await waitUntil { host.view.window != nil })
        }
    }

    @Test func hostsOverAnEmptyStore() async throws {
        let store = try await PeriscopeStore.inMemory(session: makeSession())

        let host = UIHostingController(rootView: NavigationStack {
            SpanTreeView(store: store)
        })
        try await showHosted(host) { _ in
            #expect(await waitUntil { host.view.window != nil })
        }
    }
}
