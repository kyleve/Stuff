import Foundation
@_spi(Testing) import PeriscopeCore
import PeriscopeTools
import SwiftUI
import Testing
import UIKit
import WhereTesting

@MainActor
struct LogTraceViewHostingTests {
    @Test func tracerHostsFromAnOriginEvent() async throws {
        let (store, _, _, album) = try await makeSeededStore()
        await store.write([
            makeRecord("context", date: date(1), scopes: [album.id]),
            makeRecord("origin", level: .error, date: date(2), scopes: [album.id]),
        ])
        let origin = try #require(try await store.events(matching: LogQuery()).first)

        let host = UIHostingController(rootView: NavigationStack {
            LogTraceView(store: store, origin: origin)
        })
        try show(host) { _ in
            try waitFor { host.view.window != nil }
        }
    }
}
