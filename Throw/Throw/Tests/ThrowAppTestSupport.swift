import SwiftUI
@testable import Throw
import ThrowUI
import UIKit

@MainActor
final class ThrowApplicationRuntimeSpy: ThrowApplicationRuntime {
    private(set) var backgroundCount = 0
    private(set) var foregroundCount = 0
    private(set) var connectedOutputs: [ProjectionOutput] = []
    private(set) var disconnectedOutputs: [ProjectionOutput] = []
    private(set) var appearances: [UIUserInterfaceStyle] = []

    func makeControllerView() -> AnyView {
        AnyView(EmptyView())
    }

    func makeProjectionView(presentation _: ProjectionPresentation) -> AnyView {
        AnyView(Color.black)
    }

    func projectionOutputConnected(
        _ output: ProjectionOutput,
        appearanceSink _: @escaping @MainActor (UIUserInterfaceStyle) -> Void,
    ) {
        connectedOutputs.append(output)
    }

    func projectionOutputDisconnected(_ output: ProjectionOutput) {
        disconnectedOutputs.append(output)
    }

    func applicationDidEnterBackground() {
        backgroundCount += 1
    }

    func applicationWillEnterForeground() {
        foregroundCount += 1
    }

    func controllerAppearanceDidChange(_ style: UIUserInterfaceStyle) {
        appearances.append(style)
    }
}

@MainActor
final class IdleTimerControllerSpy: IdleTimerControlling {
    private var storedIdleTimerState: Bool
    private(set) var assignedStates: [Bool] = []

    var isIdleTimerDisabled: Bool {
        get { storedIdleTimerState }
        set {
            storedIdleTimerState = newValue
            assignedStates.append(newValue)
        }
    }

    init(isIdleTimerDisabled: Bool) {
        storedIdleTimerState = isIdleTimerDisabled
    }
}
