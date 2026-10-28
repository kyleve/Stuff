import Foundation
@_spi(Testing) import PeriscopeCore
@testable import PeriscopeTools
import SwiftUI
import TestHostSupport
import Testing
import UIKit

@MainActor
struct PeriscopeViewerHostingTests {
    /// Hosts the two-tab viewer over a seeded store with density seeded from
    /// an injected (ephemeral) defaults suite — exercising the test-only
    /// `init(store:title:defaults:)` and the `\.logRowDensity` seeding path
    /// without touching the shared standard domain.
    @Test func hostsWithAnInjectedComfortableDensity() async throws {
        let (store, root, photos, album) = try await makeSeededStore()
        await store.write([
            makeRecord("a", date: date(1), scopes: [root.id]),
            makeRecord("b", date: date(2), scopes: [photos.id]),
            makeRecord("c", date: date(3), scopes: [album.id]),
        ])

        try await withEphemeralDefaults { defaults in
            PeriscopeStylesheet.Density.comfortable.save(to: defaults)
            let host = UIHostingController(rootView: NavigationStack {
                PeriscopeViewer(store: store, title: "Logs", defaults: defaults)
            })
            try await showHosted(host) { _ in
                #expect(await waitUntil { host.view.window != nil })
            }
        }
    }

    @Test func hostsOverAnEmptyStore() async throws {
        let store = try await PeriscopeStore.inMemory(session: makeSession())

        try await withEphemeralDefaults { defaults in
            let host = UIHostingController(rootView: NavigationStack {
                PeriscopeViewer(store: store, title: "Logs", defaults: defaults)
            })
            try await showHosted(host) { _ in
                #expect(await waitUntil { host.view.window != nil })
            }
        }
    }

    /// Runs `body` against a throwaway `UserDefaults` suite so the test never
    /// touches the shared standard domain.
    private func withEphemeralDefaults(
        _ body: (UserDefaults) async throws -> Void,
    ) async throws {
        let suiteName = "periscope.tools.viewer.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Could not create an ephemeral UserDefaults suite.")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try await body(defaults)
    }
}
