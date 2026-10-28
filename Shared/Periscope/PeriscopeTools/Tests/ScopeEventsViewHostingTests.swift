import Foundation
@_spi(Testing) import PeriscopeCore
@testable import PeriscopeTools
import SwiftUI
import TestHostSupport
import Testing
import UIKit

@MainActor
struct ScopeEventsViewHostingTests {
    /// Drills into a scope with nested sub-scopes and events at several
    /// depths — exercises the subtree query, the depth-indented rows, and the
    /// path title.
    @Test func hostsOverAPopulatedSubtree() async throws {
        let (store, _, photos, album) = try await makeSeededStore()
        await store.write([
            makeRecord("at photos", date: date(1), scopes: [photos.id]),
            makeRecord("in the album", date: date(2), scopes: [album.id]),
        ])

        let host = UIHostingController(rootView: NavigationStack {
            ScopeEventsView(store: store, scopeID: photos.id, scopePath: "app / photos")
        })
        try await showHosted(host) { _ in
            #expect(await waitUntil { host.view.window != nil })
        }
    }

    /// An empty subtree renders the "No Events" unavailable state rather than
    /// failing.
    @Test func hostsOverAnEmptySubtree() async throws {
        let (store, _, photos, _) = try await makeSeededStore()

        let host = UIHostingController(rootView: NavigationStack {
            ScopeEventsView(store: store, scopeID: photos.id, scopePath: "app / photos")
        })
        try await showHosted(host) { _ in
            #expect(await waitUntil { host.view.window != nil })
        }
    }
}
