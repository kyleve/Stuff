import Foundation
@_spi(Testing) import PeriscopeCore
@testable import PeriscopeTools
import SwiftUI
import TestHostSupport
import Testing
import UIKit

@MainActor
struct LogEventDetailViewHostingTests {
    /// Exercises the ambient section's load, which resolves the snapshot row
    /// from the store after the view appears.
    @Test func hostsWithAmbientState() async throws {
        let (store, _, _, album) = try await makeSeededStore()
        let offline = AmbientSnapshot(
            id: UUID(),
            values: [.network: "unsatisfied", .powerMode: "low-power"],
        )
        await store.write([
            makeRecord("failed", level: .error, date: date(1), scopes: [album.id])
                .stamped(ambient: offline),
        ])
        let event = try #require(try await store.events(matching: LogQuery()).first)
        try #require(event.ambientSnapshotID == offline.id)

        let host = UIHostingController(rootView: NavigationStack {
            LogEventDetailView(event: event, scopePath: "app / photos / album-1", store: store)
        })
        try await showHosted(host) { _ in
            #expect(await waitUntil { host.view.window != nil })
        }
    }

    @Test func hostsWithoutAmbientState() async throws {
        let (store, _, _, album) = try await makeSeededStore()
        await store.write([makeRecord("plain", date: date(1), scopes: [album.id])])
        let event = try #require(try await store.events(matching: LogQuery()).first)

        let host = UIHostingController(rootView: NavigationStack {
            LogEventDetailView(event: event, scopePath: "app / photos / album-1", store: store)
        })
        try await showHosted(host) { _ in
            #expect(await waitUntil { host.view.window != nil })
        }
    }
}
