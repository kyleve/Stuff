import Foundation
@_spi(Testing) import PeriscopeCore
@testable import PeriscopeTools
import SwiftUI
import TestHostSupport
import Testing
import UIKit

@MainActor
struct LogEventListTests {
    @Test func hostsOverSeededEventsWithDepthIndentation() async throws {
        let (store, _, photos, album) = try await makeSeededStore()
        await store.write([
            makeRecord("at photos", date: date(1), scopes: [photos.id]),
            makeRecord("in the album", date: date(2), scopes: [album.id]),
        ])
        let events = try await store.events(matching: LogQuery())

        // A non-trivial depth closure: album-1 events indent one level below
        // photos, so the row's indentation path is exercised.
        let host = UIHostingController(rootView: NavigationStack {
            LogEventList(
                events: events,
                store: store,
                scopePath: { _ in "app / photos" },
                depth: { $0.primaryScope == album.id ? 1 : 0 },
            )
        })
        try await showHosted(host) { _ in
            #expect(await waitUntil { host.view.window != nil })
        }
    }

    @Test func hostsOverAnEmptyEventList() async throws {
        let store = try await PeriscopeStore.inMemory(session: makeSession())

        let host = UIHostingController(rootView: NavigationStack {
            LogEventList(events: [], store: store, scopePath: { _ in "" })
        })
        try await showHosted(host) { _ in
            #expect(await waitUntil { host.view.window != nil })
        }
    }
}
