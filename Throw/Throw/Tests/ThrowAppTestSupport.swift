@testable import Throw
@_spi(Testing) @testable import ThrowUI
import UIKit

@MainActor
final class ThrowApplicationRuntimeSpy: ThrowApplicationRuntime {
    let session: ThrowSession

    private(set) var controllerSceneEvents: [RecordedControllerSceneEvent] = []
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

    func controllerScene(
        _ id: ControllerSceneID,
        didReceive event: ControllerSceneLifecycleEvent,
    ) {
        controllerSceneEvents.append(RecordedControllerSceneEvent(id: id, event: event))
    }

    func controllerAppearanceDidChange(_ style: UIUserInterfaceStyle) {
        appearances.append(style)
    }

    func sessionOutputDemandDidChange() {
        outputDemandChangeCount += 1
    }
}

struct RecordedControllerSceneEvent: Equatable {
    let id: ControllerSceneID
    let event: ControllerSceneLifecycleEvent
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

@MainActor
final class BackgroundExecutionLeaseSpy: BackgroundExecutionLease {
    private(set) var endCallCount = 0
    private var awaitedEndCallCount = 0
    private var endContinuation: CheckedContinuation<Void, Never>?

    func end() {
        endCallCount += 1
        if endCallCount >= awaitedEndCallCount {
            endContinuation?.resume()
            endContinuation = nil
        }
    }

    func waitForEndCallCount(_ expectedCount: Int) async {
        guard endCallCount < expectedCount else { return }
        awaitedEndCallCount = expectedCount
        await withCheckedContinuation { continuation in
            endContinuation = continuation
        }
    }
}

@MainActor
final class BackgroundExecutionLeaserSpy: BackgroundExecutionLeasing {
    private(set) var beginCallCount = 0
    private(set) var lastLease: BackgroundExecutionLeaseSpy?
    private var expirationHandler: (@MainActor @Sendable () -> Void)?

    func begin(
        name _: String,
        expirationHandler: @escaping @MainActor @Sendable () -> Void,
    ) -> any BackgroundExecutionLease {
        beginCallCount += 1
        let lease = BackgroundExecutionLeaseSpy()
        lastLease = lease
        self.expirationHandler = expirationHandler
        return lease
    }

    func expire() {
        expirationHandler?()
        expirationHandler = nil
    }
}
