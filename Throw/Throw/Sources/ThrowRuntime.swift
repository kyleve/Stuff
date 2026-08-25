import SwiftUI
import ThrowUI
import UIKit

@MainActor
protocol IdleTimerControlling: AnyObject {
    var isIdleTimerDisabled: Bool { get set }
}

extension UIApplication: IdleTimerControlling {}

/// The class-bound handoff shared by the SwiftUI app and platform-created scenes.
@MainActor
protocol ThrowApplicationRuntime: AnyObject {
    func makeControllerView() -> AnyView
    func makeProjectionView(presentation: ProjectionPresentation) -> AnyView
    func projectionOutputConnected(
        _ output: ProjectionOutput,
        appearanceSink: @escaping @MainActor (UIUserInterfaceStyle) -> Void,
    )
    func projectionOutputDisconnected(_ output: ProjectionOutput)
    func applicationDidEnterBackground()
    func applicationWillEnterForeground()
    func controllerAppearanceDidChange(_ style: UIUserInterfaceStyle)
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

    init(session: ThrowSession, idleTimerController: any IdleTimerControlling) {
        self.session = session
        self.idleTimerController = idleTimerController
    }

    static func live() -> ThrowRuntime {
        ThrowRuntime(
            session: .live(),
            idleTimerController: UIApplication.shared,
        )
    }

    func makeControllerView() -> AnyView {
        AnyView(
            RuntimeControllerView(
                session: session,
                outputDemandDidChange: { [weak self] in
                    self?.sessionOutputDemandDidChange()
                },
            )
            .throwBroadwayRoot(),
        )
    }

    func makeProjectionView(presentation: ProjectionPresentation) -> AnyView {
        AnyView(
            ProjectionSurface(session: session, presentation: presentation)
                .throwBroadwayRoot(),
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

    func applicationDidEnterBackground() {
        session.applicationDidEnterBackground()
    }

    func applicationWillEnterForeground() {
        session.applicationWillEnterForeground()
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

private struct RuntimeControllerView: View {
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
