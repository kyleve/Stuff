import SwiftUI
import ThrowUI
import UIKit

/// Hosts the shared projection surface on one noninteractive external scene.
@MainActor
final class ExternalDisplaySceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    private var output: ProjectionOutput?
    private weak var runtime: (any ThrowApplicationRuntime)?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options _: UIScene.ConnectionOptions,
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        guard let runtime = Self.runtime(from: UIApplication.shared.delegate) else {
            assertionFailure("Throw external scene connected without the process runtime")
            connectBlackFallback(to: windowScene)
            return
        }

        let id = ProjectionOutputID(rawValue: "external:\(session.persistentIdentifier)")
        let output = ProjectionOutput.externalDisplay(id)
        let host = UIHostingController(
            rootView: ProjectionSurface(
                session: runtime.session,
                presentation: .externalDisplay,
            )
            .throwBroadwayRoot(),
        )
        host.view.backgroundColor = .black
        host.view.isOpaque = true

        let window = UIWindow(windowScene: windowScene)
        window.backgroundColor = .black
        window.rootViewController = host
        window.makeKeyAndVisible()

        self.window = window
        connectProjectionOutput(output, runtime: runtime) { [weak host] style in
            host?.overrideUserInterfaceStyle = style
        }
    }

    func sceneDidDisconnect(_: UIScene) {
        disconnectProjectionOutput()
        window = nil
    }

    func windowScene(
        _: UIWindowScene,
        didUpdateEffectiveGeometry _: UIWindowScene.Geometry,
    ) {
        window?.setNeedsLayout()
        window?.rootViewController?.view.setNeedsLayout()
    }

    static func runtime(
        from applicationDelegate: (any UIApplicationDelegate)?,
    ) -> (any ThrowApplicationRuntime)? {
        (applicationDelegate as? any ThrowRuntimeProviding)?.runtime
    }

    func connectProjectionOutput(
        _ output: ProjectionOutput,
        runtime: any ThrowApplicationRuntime,
        appearanceSink: @escaping @MainActor (UIUserInterfaceStyle) -> Void,
    ) {
        self.runtime = runtime
        self.output = output
        runtime.projectionOutputConnected(output, appearanceSink: appearanceSink)
    }

    func disconnectProjectionOutput() {
        guard let output, let runtime else { return }
        runtime.projectionOutputDisconnected(output)
        self.output = nil
        self.runtime = nil
    }

    private func connectBlackFallback(to windowScene: UIWindowScene) {
        let controller = UIViewController()
        controller.view.backgroundColor = .black
        let window = UIWindow(windowScene: windowScene)
        window.backgroundColor = .black
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
    }
}
