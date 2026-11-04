import UIKit

final class DisplayProbeScene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo _: UISceneSession,
        options _: UIScene.ConnectionOptions,
    ) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UINavigationController(
            rootViewController: DisplayInspectorController(),
        )
        self.window = window
        window.makeKeyAndVisible()
    }
}
