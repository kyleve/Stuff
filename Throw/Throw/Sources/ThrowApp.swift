import SwiftUI
import ThrowUI
import UIKit

@main
struct ThrowApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            appDelegate.runtime.makeControllerView()
                .background {
                    ControllerSceneBridge(
                        appearanceDidChange: appDelegate.runtime
                            .controllerAppearanceDidChange,
                        registerAccessory: appDelegate.registerExternalDisplayAccessory,
                        unregisterAccessory: appDelegate.unregisterExternalDisplayAccessory,
                    )
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
                }
        }
    }
}

/// Platform handoff from every UIKit-created scene to the process runtime.
@MainActor
protocol ThrowRuntimeProviding: UIApplicationDelegate {
    var runtime: any ThrowApplicationRuntime { get }
}

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate, ThrowRuntimeProviding {
    let runtime: any ThrowApplicationRuntime

    // Type-erased because Swift does not permit iOS 27-only stored-property
    // types in an app that still deploys to iOS 26. Both UIKit values are
    // NSObject subclasses; retaining them keeps the accessory registered.
    private var externalDisplayAccessory: AnyObject?
    private var externalDisplayRegistration: AnyObject?
    private weak var externalDisplayAccessoryOwner: UIViewController?
    private var accessoryControllers: [ObjectIdentifier: WeakControllerReference] = [:]

    override init() {
        runtime = ThrowRuntime.live()
        super.init()
    }

    init(runtime: any ThrowApplicationRuntime) {
        self.runtime = runtime
        super.init()
    }

    func applicationDidEnterBackground(_: UIApplication) {
        runtime.applicationDidEnterBackground()
    }

    func applicationWillEnterForeground(_: UIApplication) {
        runtime.applicationWillEnterForeground()
    }

    func registerExternalDisplayAccessory(from controller: UIViewController) {
        guard #available(iOS 27.0, *) else { return }
        pruneAccessoryControllers()
        accessoryControllers[ObjectIdentifier(controller)] = WeakControllerReference(controller)

        if externalDisplayAccessoryOwner == nil {
            externalDisplayAccessory = nil
            externalDisplayRegistration = nil
        }
        guard externalDisplayRegistration == nil else { return }
        installExternalDisplayAccessory(on: controller)
    }

    func unregisterExternalDisplayAccessory(from controller: UIViewController) {
        guard #available(iOS 27.0, *) else { return }
        accessoryControllers[ObjectIdentifier(controller)] = nil
        guard externalDisplayAccessoryOwner === controller else { return }

        if let registration = externalDisplayRegistration as? UISceneAccessoryRegistration {
            controller.unregisterSceneAccessory(registration)
        }
        externalDisplayAccessory = nil
        externalDisplayRegistration = nil
        externalDisplayAccessoryOwner = nil

        pruneAccessoryControllers()
        if let replacement = accessoryControllers.values.lazy.compactMap(\.controller).first {
            installExternalDisplayAccessory(on: replacement)
        }
    }

    @available(iOS 27.0, *)
    private func installExternalDisplayAccessory(on controller: UIViewController) {
        guard externalDisplayRegistration == nil else { return }

        let configuration = Self.externalDisplayConfiguration()
        let accessory = UISceneAccessory.externalNonInteractive(
            sceneConfiguration: configuration,
        )
        let registration = controller.registerSceneAccessory(accessory)
        registration.isEnabled = true
        externalDisplayAccessory = accessory
        externalDisplayRegistration = registration
        externalDisplayAccessoryOwner = controller
    }

    private func pruneAccessoryControllers() {
        accessoryControllers = accessoryControllers.filter { $0.value.controller != nil }
    }

    static func externalDisplayConfiguration() -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: "Throw External Display",
            sessionRole: .windowExternalDisplayNonInteractive,
        )
        configuration.delegateClass = ExternalDisplaySceneDelegate.self
        return configuration
    }
}

private struct ControllerSceneBridge: UIViewControllerRepresentable {
    let appearanceDidChange: @MainActor (UIUserInterfaceStyle) -> Void
    let registerAccessory: @MainActor (UIViewController) -> Void
    let unregisterAccessory: @MainActor (UIViewController) -> Void

    func makeUIViewController(context _: Context) -> ControllerSceneBridgeController {
        ControllerSceneBridgeController(
            appearanceDidChange: appearanceDidChange,
            registerAccessory: registerAccessory,
            unregisterAccessory: unregisterAccessory,
        )
    }

    func updateUIViewController(
        _ controller: ControllerSceneBridgeController,
        context _: Context,
    ) {
        controller.reportCurrentState()
    }

    static func dismantleUIViewController(
        _ controller: ControllerSceneBridgeController,
        coordinator _: (),
    ) {
        controller.disconnect()
    }
}

private final class ControllerSceneBridgeController: UIViewController {
    private let appearanceDidChange: @MainActor (UIUserInterfaceStyle) -> Void
    private let registerAccessory: @MainActor (UIViewController) -> Void
    private let unregisterAccessory: @MainActor (UIViewController) -> Void

    init(
        appearanceDidChange: @escaping @MainActor (UIUserInterfaceStyle) -> Void,
        registerAccessory: @escaping @MainActor (UIViewController) -> Void,
        unregisterAccessory: @escaping @MainActor (UIViewController) -> Void,
    ) {
        self.appearanceDidChange = appearanceDidChange
        self.registerAccessory = registerAccessory
        self.unregisterAccessory = unregisterAccessory
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (
            controller: ControllerSceneBridgeController,
            _: UITraitCollection,
        ) in
            controller.reportCurrentState()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        reportCurrentState()
        registerAccessory(self)
    }

    func reportCurrentState() {
        appearanceDidChange(traitCollection.userInterfaceStyle)
    }

    func disconnect() {
        unregisterAccessory(self)
    }
}

private final class WeakControllerReference {
    weak var controller: UIViewController?

    init(_ controller: UIViewController) {
        self.controller = controller
    }
}
