import SwiftUI
import ThrowUI
import UIKit

@MainActor
protocol IdleTimerControlling: AnyObject {
    var isIdleTimerDisabled: Bool { get set }
}

extension UIApplication: IdleTimerControlling {}

/// The stable UIKit identity for one controller scene in this process.
struct ControllerSceneID: Hashable {
    let rawValue: String

    init(rawValue: String) {
        precondition(rawValue.isEmpty == false, "A controller scene ID must not be empty")
        self.rawValue = rawValue
    }

    init(session: UISceneSession) {
        self.init(rawValue: session.persistentIdentifier)
    }
}

/// A foreground-membership transition emitted by one controller scene.
enum ControllerSceneLifecycleEvent: Equatable {
    case willEnterForeground
    case didEnterBackground
    case didDisconnect
}

/// The class-bound handoff shared by the SwiftUI app and platform-created scenes.
@MainActor
protocol ThrowApplicationRuntime: AnyObject {
    var session: ThrowSession { get }

    func projectionOutputConnected(
        _ output: ProjectionOutput,
        appearanceSink: @escaping @MainActor (UIUserInterfaceStyle) -> Void,
    )
    func projectionOutputDisconnected(_ output: ProjectionOutput)
    func controllerScene(
        _ id: ControllerSceneID,
        didReceive event: ControllerSceneLifecycleEvent,
    )
    func controllerAppearanceDidChange(_ style: UIUserInterfaceStyle)
    func sessionOutputDemandDidChange()
}

/// Owns Throw's one UI session and the process-level output lifecycle.
@MainActor
final class ThrowRuntime: ThrowApplicationRuntime {
    let session: ThrowSession

    private let idleTimerController: any IdleTimerControlling
    private var activeOutputs: [ProjectionOutputID: ProjectionOutput] = [:]
    private var appearanceSinks: [ProjectionOutputID: @MainActor (UIUserInterfaceStyle) -> Void] =
        [:]
    private var previousIdleTimerState: Bool?
    private var controllerAppearance: UIUserInterfaceStyle = .unspecified
    private var foregroundControllerScenes: Set<ControllerSceneID> = []

    init(session: ThrowSession, idleTimerController: any IdleTimerControlling) {
        self.session = session
        self.idleTimerController = idleTimerController
        session.controllerForegroundPresenceDidChange(false)
        session.startLaunch()
    }

    static func live() -> ThrowRuntime {
        ThrowRuntime(
            session: .live(),
            idleTimerController: UIApplication.shared,
        )
    }

    func projectionOutputConnected(
        _ output: ProjectionOutput,
        appearanceSink: @escaping @MainActor (UIUserInterfaceStyle) -> Void,
    ) {
        let id = Self.id(for: output)
        appearanceSinks[id] = appearanceSink
        appearanceSink(controllerAppearance)

        guard activeOutputs[id] == nil else { return }
        activeOutputs[id] = output
        session.projectionOutputConnected(output)
        sessionOutputDemandDidChange()
    }

    func projectionOutputDisconnected(_ output: ProjectionOutput) {
        let id = Self.id(for: output)
        appearanceSinks[id] = nil
        guard let connectedOutput = activeOutputs.removeValue(forKey: id) else { return }
        session.projectionOutputDisconnected(connectedOutput)
        sessionOutputDemandDidChange()
    }

    func controllerScene(
        _ id: ControllerSceneID,
        didReceive event: ControllerSceneLifecycleEvent,
    ) {
        let previouslyHadForegroundController = foregroundControllerScenes.isEmpty == false
        switch event {
            case .willEnterForeground:
                foregroundControllerScenes.insert(id)
            case .didEnterBackground, .didDisconnect:
                foregroundControllerScenes.remove(id)
        }
        let hasForegroundController = foregroundControllerScenes.isEmpty == false
        guard hasForegroundController != previouslyHadForegroundController else { return }
        session.controllerForegroundPresenceDidChange(hasForegroundController)
    }

    func controllerAppearanceDidChange(_ style: UIUserInterfaceStyle) {
        guard controllerAppearance != style else { return }
        controllerAppearance = style
        for sink in appearanceSinks.values {
            sink(style)
        }
    }

    func sessionOutputDemandDidChange() {
        reconcileIdleTimer(hasOutputDemand: session.hasProjectionOutputDemand)
    }

    private static func id(for output: ProjectionOutput) -> ProjectionOutputID {
        switch output {
            case let .externalDisplay(id), let .fullScreen(id), let .preview(id),
                 let .calibration(id):
                id
        }
    }

    private func reconcileIdleTimer(hasOutputDemand: Bool) {
        if hasOutputDemand {
            guard previousIdleTimerState == nil else { return }
            previousIdleTimerState = idleTimerController.isIdleTimerDisabled
            idleTimerController.isIdleTimerDisabled = true
        } else {
            guard let previousIdleTimerState else { return }
            idleTimerController.isIdleTimerDisabled = previousIdleTimerState
            self.previousIdleTimerState = nil
        }
    }
}

struct RuntimeControllerView: View {
    let session: ThrowSession
    let outputDemandDidChange: @MainActor () -> Void

    var body: some View {
        ThrowRootView(session: session)
            .onChange(of: session.projectionOutputCount, initial: true) {
                _, _ in
                outputDemandDidChange()
            }
    }
}
