import Foundation
@_spi(Testing) import PeriscopeCore
@testable import PeriscopeTools
import SwiftUI
import TestHostSupport
import Testing
import UIKit

@MainActor
struct LogInspectableHostingTests {
    private func makeInspector() async throws -> PeriscopeInspector {
        let store = try await PeriscopeStore.inMemory(session: makeSession())
        let system = Periscope(configuration: Periscope.Configuration(), sinks: [])
        return PeriscopeInspector(system: system, store: store)
    }

    @Test func inspectableViewsHostWithTheModeOff() async throws {
        let inspector = try await makeInspector()
        let log = Log<PhotoLogs>(system: inspector.system)

        let host = UIHostingController(rootView: Text("Payment Row")
            .logInspectable(log)
            .periscopeInspector(inspector))
        try show(host) { _ in
            try waitFor { host.view.window != nil }
        }
    }

    @Test func inspectableViewsHostWithTheModeOn() async throws {
        let inspector = try await makeInspector()
        inspector.isEnabled = true
        let log = Log<PhotoLogs>(system: inspector.system)

        let host = UIHostingController(rootView: Text("Payment Row")
            .logInspectable(log)
            .periscopeInspector(inspector))
        try show(host) { _ in
            try waitFor { host.view.window != nil }
        }
    }

    @Test func inspectorViewHostsOverSeededEvents() async throws {
        let (store, _, photos, album) = try await makeSeededStore()
        await store.write([makeRecord("deep", date: date(1), scopes: [album.id])])

        let host = UIHostingController(rootView: NavigationStack {
            LogInspectorView(store: store, scopes: [photos.id], limit: 500)
        })
        try show(host) { _ in
            try waitFor { host.view.window != nil }
        }
    }
}
