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
        window.rootViewController = UIViewController()
        // Marks this as the window `TestHostSupport.hostKeyWindow()` / `show()` target.
        window.isMainTestHostWindow = true
        window.makeKeyAndVisible()
        self.window = window
    }
}
