import Foundation
@_spi(Testing) import PeriscopeCore
import PeriscopeTools
import SwiftUI
import TestHostSupport
import Testing
import UIKit

@MainActor
struct SpanHistoryViewHostingTests {
    @Test func hostsOverRecordedSpans() async throws {
        let (store, root, _, _) = try await makeSeededStore()
        await store.write([
            spanEnded(SpanID(), name: "save", at: date(0), duration: .seconds(1), scope: root.id),
            spanEnded(SpanID(), name: "save", at: date(1), duration: .seconds(2), scope: root.id),
            spanEnded(SpanID(), name: "load", at: date(2), duration: .seconds(1), scope: root.id),
        ])

        let host = UIHostingController(rootView: NavigationStack {
            SpanHistoryView(store: store)
        })
        try await showHosted(host) { _ in
            #expect(await waitUntil { host.view.window != nil })
        }
    }

    @Test func hostsOverAnEmptyStore() async throws {
        let store = try await PeriscopeStore.inMemory(session: makeSession())

        let host = UIHostingController(rootView: NavigationStack {
            SpanHistoryView(store: store)
        })
        try await showHosted(host) { _ in
            #expect(await waitUntil { host.view.window != nil })
        }
    }
}
