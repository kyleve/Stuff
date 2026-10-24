import SwiftUI
import ThrowUI
import UIKit

@main
struct ThrowApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RuntimeControllerView(
                session: appDelegate.runtime.session,
                outputDemandDidChange: appDelegate.runtime.sessionOutputDemandDidChange,
                externalOutputConnected: appDelegate.runtime.projectionOutputConnected,
                externalOutputDisconnected: appDelegate.runtime.projectionOutputDisconnected,
            )
            .throwBroadwayRoot()
            .background {
                ControllerSceneBridge(
                    lifecycleDidChange: appDelegate.runtime
                        .controllerScene(_:didReceive:),
                )
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    let runtime: any ThrowApplicationRuntime

    override init() {
        runtime = ThrowRuntime.live()
        super.init()
    }

    init(runtime: any ThrowApplicationRuntime) {
        self.runtime = runtime
        super.init()
    }
}

private struct ControllerSceneBridge: UIViewControllerRepresentable {
    let lifecycleDidChange:
        @MainActor (ControllerSceneID, ControllerSceneLifecycleEvent) -> Void

    func makeUIViewController(context _: Context) -> ControllerSceneBridgeController {
        ControllerSceneBridgeController(lifecycleDidChange: lifecycleDidChange)
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
    private let lifecycleDidChange:
        @MainActor (ControllerSceneID, ControllerSceneLifecycleEvent) -> Void
    private weak var observedControllerScene: UIWindowScene?
    private var observedControllerSceneID: ControllerSceneID?

    init(
        lifecycleDidChange: @escaping @MainActor (
            ControllerSceneID,
            ControllerSceneLifecycleEvent,
        ) -> Void,
    ) {
        self.lifecycleDidChange = lifecycleDidChange
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
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        reportCurrentState()
    }

    func reportCurrentState() {
        observeControllerSceneIfNeeded()
    }

    func disconnect() {
        stopObservingControllerScene()
    }

    private func observeControllerSceneIfNeeded() {
        guard let windowScene = view.window?.windowScene else { return }
        guard observedControllerScene !== windowScene else { return }
        stopObservingControllerScene()

        let id = ControllerSceneID(session: windowScene.session)
        observedControllerScene = windowScene
        observedControllerSceneID = id
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(controllerSceneWillEnterForeground(_:)),
            name: UIScene.willEnterForegroundNotification,
            object: windowScene,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(controllerSceneDidEnterBackground(_:)),
            name: UIScene.didEnterBackgroundNotification,
            object: windowScene,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(controllerSceneDidDisconnect(_:)),
            name: UIScene.didDisconnectNotification,
            object: windowScene,
        )
        lifecycleDidChange(id, Self.initialLifecycleEvent(for: windowScene.activationState))
    }

    private func stopObservingControllerScene() {
        guard let id = observedControllerSceneID else { return }
        NotificationCenter.default.removeObserver(self)
        observedControllerScene = nil
        observedControllerSceneID = nil
        lifecycleDidChange(id, .didDisconnect)
    }

    @objc private func controllerSceneWillEnterForeground(_ notification: Notification) {
        report(.willEnterForeground, from: notification)
    }

    @objc private func controllerSceneDidEnterBackground(_ notification: Notification) {
        report(.didEnterBackground, from: notification)
    }

    @objc private func controllerSceneDidDisconnect(_ notification: Notification) {
        report(.didDisconnect, from: notification)
    }

    private func report(
        _ event: ControllerSceneLifecycleEvent,
        from notification: Notification,
    ) {
        guard let notificationScene = notification.object as? UIWindowScene,
              notificationScene === observedControllerScene,
              let id = observedControllerSceneID
        else { return }
        lifecycleDidChange(id, event)
    }

    private static func initialLifecycleEvent(
        for activationState: UIScene.ActivationState,
    ) -> ControllerSceneLifecycleEvent {
        switch activationState {
            case .foregroundActive, .foregroundInactive:
                return .willEnterForeground
            case .background, .unattached:
                return .didEnterBackground
            @unknown default:
                assertionFailure("Unknown controller scene activation state")
                return .didEnterBackground
        }
    }
}
