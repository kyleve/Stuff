import Foundation
@_spi(Testing) import PeriscopeCore
import PeriscopeTools
import SwiftUI
import TestHostSupport
import Testing
import UIKit

@LogScope("AppLogs")
private enum AppLogs {}

@MainActor
struct OpenSpansViewHostingTests {
    @Test func hostsWithOpenSpans() throws {
        let system = Periscope(configuration: Periscope.Configuration(), sinks: [])
        let log = Log<AppLogs>(system: system)(for: "checkout")
        log.begin(for: "pay_1", lifetime: .bounded(budget: .seconds(120)))
        log.begin(for: "pay_2", lifetime: .indefinite)

        let host = UIHostingController(rootView: NavigationStack {
            OpenSpansView(system: system)
        })
        try show(host) { _ in
            try waitFor { host.view.window != nil }
        }
    }

    @Test func hostsEmpty() throws {
        let system = Periscope(configuration: Periscope.Configuration(), sinks: [])

        let host = UIHostingController(rootView: NavigationStack {
            OpenSpansView(system: system)
        })
        try show(host) { _ in
            try waitFor { host.view.window != nil }
        }
    }
}
