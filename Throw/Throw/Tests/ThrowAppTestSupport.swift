@testable import Throw
@_spi(Testing) @testable import ThrowUI
import UIKit

@MainActor
final class ThrowApplicationRuntimeSpy: ThrowApplicationRuntime {
    let session: ThrowSession

    private(set) var backgroundCount = 0
    private(set) var foregroundCount = 0
    private(set) var connectedOutputs: [ProjectionOutput] = []
    private(set) var disconnectedOutputs: [ProjectionOutput] = []
    private(set) var appearances: [UIUserInterfaceStyle] = []
    private(set) var outputDemandChangeCount = 0

    init(session: ThrowSession) {
        self.session = session
    }

    convenience init() {
        self.init(session: .fixture())
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

    func sessionOutputDemandDidChange() {
        outputDemandChangeCount += 1
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
