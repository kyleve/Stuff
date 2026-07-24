#if canImport(UIKit)
    import Foundation
    import PortholeCore
    @_spi(Testing) import PortholeKit
    import TestHostSupport
    import Testing
    import UIKit

    @MainActor
    struct ViewTreeConnectorTests {
        private func makeSession() -> (Porthole, TestSessionClient) {
            let porthole = Porthole(
                configuration: PortholeConfiguration(
                    appName: "UITest",
                    bundleID: "com.stuff.uitest",
                ),
            )
            let (deviceTransport, clientTransport) = LoopbackTransport.makePair()
            porthole.attach(transport: deviceTransport)
            return (porthole, TestSessionClient(transport: clientTransport))
        }

        /// Hosts `viewController` in the test host window across an async body
        /// (the sync `show(_:perform:)` can't await).
        private func hosted(
            _ viewController: UIViewController,
            _ body: () async throws -> Void,
        ) async throws {
            try waitFor { hostKeyWindow()?.rootViewController != nil }
            guard let root = hostKeyWindow()?.rootViewController else { return }
            root.addChild(viewController)
            viewController.view.frame = root.view.bounds
            root.view.addSubview(viewController.view)
            viewController.didMove(toParent: root)
            viewController.view.layoutIfNeeded()
            defer {
                viewController.willMove(toParent: nil)
                viewController.view.removeFromSuperview()
                viewController.removeFromParent()
            }
            try await body()
        }

        @Test func windowsSourceReportsAtLeastTheHostWindow() async throws {
            let (_, client) = makeSession()
            try await hosted(UIViewController()) {
                await client.start()
                let response = try await client.send(.query(
                    ref: .init(connector: "ui", source: "windows"),
                    query: PortholeQuery(),
                ))
                guard case let .queryResult(page) = response else {
                    Issue.record("Expected queryResult, got \(response)")
                    return
                }
                #expect(!page.rows.isEmpty)
                #expect(page.rows.first?["class"]?.stringValue != nil)
            }
        }

        @Test func viewTreeReflectsAKnownHierarchy() async throws {
            let container = UIViewController()
            let tagged = UIView()
            tagged.accessibilityIdentifier = "porthole-probe-view"
            container.view.addSubview(tagged)

            let (_, client) = makeSession()
            try await hosted(container) {
                await client.start()
                let response = try await client.send(.query(
                    ref: .init(connector: "ui", source: "view-tree"),
                    query: PortholeQuery(filters: ["maxDepth": 50]),
                ))
                guard case let .queryResult(page) = response, let root = page.rows.first else {
                    Issue.record("Expected a view-tree row, got \(response)")
                    return
                }
                #expect(root["class"]?.stringValue != nil)
                #expect(containsIdentifier("porthole-probe-view", in: root))
            }
        }

        @Test func accessibilityTreeReturnsARootRow() async throws {
            let (_, client) = makeSession()
            try await hosted(UIViewController()) {
                await client.start()
                let response = try await client.send(.query(
                    ref: .init(connector: "ui", source: "accessibility-tree"),
                    query: PortholeQuery(),
                ))
                guard case let .queryResult(page) = response else {
                    Issue.record("Expected queryResult, got \(response)")
                    return
                }
                #expect(page.rows.count == 1)
            }
        }

        @Test func screenshotReturnsDecodablePNG() async throws {
            let container = UIViewController()
            container.view.backgroundColor = .systemBlue
            let (_, client) = makeSession()
            try await hosted(container) {
                await client.start()
                let response = try await client.send(.invokeAction(
                    ref: .init(connector: "ui", action: "screenshot"),
                    parameters: ["windowIndex": 0],
                ))
                guard case let .actionResult(value) = response else {
                    Issue.record("Expected actionResult, got \(response)")
                    return
                }
                let data = try #require(value["image"]?.dataValue)
                #expect(UIImage(data: data) != nil)
                #expect((value["width"]?.intValue ?? 0) > 0)
            }
        }

        @Test func openURLRejectsAnInvalidURL() async throws {
            let (_, client) = makeSession()
            try await hosted(UIViewController()) {
                await client.start()
                let response = try await client.send(.invokeAction(
                    ref: .init(connector: "ui", action: "open-url"),
                    parameters: ["url": ""],
                ))
                guard case .failure = response else {
                    Issue.record("Expected failure for an empty URL, got \(response)")
                    return
                }
            }
        }

        private func containsIdentifier(_ id: String, in node: PortholeValue) -> Bool {
            if node["accessibilityIdentifier"]?.stringValue == id { return true }
            for child in node["children"]?.arrayValue ?? [] {
                if containsIdentifier(id, in: child) { return true }
            }
            return false
        }
    }
#endif
