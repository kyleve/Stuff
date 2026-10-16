import TestHostSupport
import UIKit

@MainActor
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo _: UISceneSession,
        options _: UIScene.ConnectionOptions,
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = TestRootViewController()
        // Marks this as the window `TestHostSupport.hostKeyWindow()` / `show()` target.
        window.isMainTestHostWindow = true
        window.makeKeyAndVisible()
        self.window = window
    }
}

/// Keeps virtual phone and tablet frames independent of the simulator's side bar.
private final class TestRootViewController: UIViewController {
    override var preferredVerticalBarBehavior: UIVerticalBarBehavior {
        .disabled
    }
}
