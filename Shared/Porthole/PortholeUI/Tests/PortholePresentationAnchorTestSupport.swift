#if canImport(UIKit)
    import PortholeRuntime
    import PortholeUI
    import SwiftUI
    import TestHostSupport
    import Testing
    import UIKit

    /// Each test owns a non-key window so modal work cannot replace another suite's host content.
    @MainActor
    struct PortholePresentationAnchorFixture {
        let controller: PortholePresentationController
        let context: PortholeContext
        let root: PortholeAnchorRootController
        let modal = PortholeAnchorModalController()
        let window: UIWindow

        init(coversRoot: Bool) async throws {
            try await Self.wait(
                "test host scene",
                diagnostics: { "hostKeyWindow=\(String(describing: hostKeyWindow()))" },
            ) {
                hostKeyWindow()?.windowScene != nil
            }
            let scene = try #require(hostKeyWindow()?.windowScene)
            let registry = PortholeRegistry(journal: .init(url: nil), objectLimit: 20)
            await registry.setEnabled(true)
            let scope = await registry.createScope(id: .init(rawValue: "test.application"))
            controller = PortholePresentationController(
                registry: registry,
                applicationTitle: "Test",
            )
            context = PortholeContext(
                id: .init(rawValue: "selected.issue"),
                title: "Border drift",
                scope: scope,
                capturedAt: Date(timeIntervalSince1970: 1),
                values: .object(["day": .string("2026-09-13")]),
                objects: [],
                links: [],
                source: nil,
            )
            root = PortholeAnchorRootController(rootView: AnyView(Color.clear
                    .portholePresentationAnchor(controller: controller)))
            window = UIWindow(windowScene: scene)
            window.frame = scene.effectiveGeometry.coordinateSpace.bounds
            window.layer.speed = 100
            window.rootViewController = root
            window.isHidden = false
            root.view.layoutIfNeeded()
            modal.view.backgroundColor = .systemBackground
            modal.modalPresentationStyle = coversRoot ? .fullScreen : .pageSheet
            try await wait("root appearance") { root.view.window === window && root.hasAppeared }
        }

        func presentApplicationModal() {
            root.present(modal, animated: false)
        }

        func close() async {
            controller.dismiss()
            do {
                try await wait("debugger cleanup") {
                    modal.presentedViewController == nil && !modal.isBeingPresented
                        && modal.transitionCoordinator == nil
                }
            } catch { Issue.record(error) }
            root.dismiss(animated: false)
            do {
                try await wait("application modal cleanup") {
                    root.presentedViewController == nil && root.transitionCoordinator == nil
                }
            } catch { Issue.record(error) }
            window.isHidden = true
            window.rootViewController = nil
        }

        func wait(_ condition: String, predicate: () -> Bool) async throws {
            try await Self.wait(condition, diagnostics: {
                "rootAppeared=\(root.hasAppeared), rootAttached=\(root.view.window === window), " +
                    "modalAppeared=\(modal.hasAppeared), modalPresenting=\(modal.isBeingPresented), " +
                    "modalDismissing=\(modal.isBeingDismissed), " +
                    "presented=\(String(describing: modal.presentedViewController)), " +
                    "session=\(String(describing: controller.sessionID))"
            }, predicate: predicate)
        }

        private static func wait(
            _ condition: String,
            diagnostics: () -> String,
            predicate: () -> Bool,
        ) async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(10))
            while !predicate() {
                try Task.checkCancellation()
                guard ContinuousClock.now < deadline else {
                    throw PortholeAnchorWaitError(condition: condition, state: diagnostics())
                }
                // UIKit needs run-loop work; deferred MainActor completions also need a task yield.
                // The predicate, rather than an elapsed delay, determines readiness.
                advanceUIKitRunLoop()
                await Task.yield()
            }
        }

        private static func advanceUIKitRunLoop() {
            _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.001))
        }
    }

    @MainActor final class PortholeAnchorRootController: UIHostingController<AnyView> {
        private(set) var hasAppeared = false
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            hasAppeared = true
        }
    }

    @MainActor final class PortholeAnchorModalController: UIViewController {
        private(set) var hasAppeared = false
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            hasAppeared = true
        }
    }

    struct PortholeAnchorWaitError: Error, CustomStringConvertible {
        let condition: String
        let state: String
        var description: String {
            "Timed out waiting for \(condition): \(state)"
        }
    }
#endif
