import UIKit

@MainActor
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options _: UIScene.ConnectionOptions,
    ) -> UISceneConfiguration {
        let configuration = connectingSceneSession.configuration
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}
