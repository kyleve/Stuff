import Testing
@testable import Throw
@_spi(Testing) import ThrowUI
import UIKit

@MainActor
struct ThrowRuntimeTests {
    @Test func firstAndLastOutputOwnIdleTimerRestoration() {
        let idleTimer = IdleTimerControllerSpy(isIdleTimerDisabled: false)
        let runtime = ThrowRuntime(
            session: .fixture(),
            idleTimerController: idleTimer,
        )
        let external = ProjectionOutput.externalDisplay(
            ProjectionOutputID(rawValue: "external-test"),
        )
        let preview = ProjectionOutput.preview(
            ProjectionOutputID(rawValue: "preview-test"),
        )

        runtime.projectionOutputConnected(external) { _ in }
        runtime.projectionOutputConnected(preview) { _ in }
        #expect(idleTimer.isIdleTimerDisabled)

        runtime.projectionOutputDisconnected(external)
        #expect(idleTimer.isIdleTimerDisabled)

        runtime.projectionOutputDisconnected(preview)
        #expect(idleTimer.isIdleTimerDisabled == false)
    }

    @Test func duplicateOutputIdentityDoesNotRequireAnExtraDisconnect() {
        let idleTimer = IdleTimerControllerSpy(isIdleTimerDisabled: false)
        let runtime = ThrowRuntime(
            session: .fixture(),
            idleTimerController: idleTimer,
        )
        let output = ProjectionOutput.externalDisplay(
            ProjectionOutputID(rawValue: "external-test"),
        )

        runtime.projectionOutputConnected(output) { _ in }
        runtime.projectionOutputConnected(output) { _ in }
        runtime.projectionOutputDisconnected(output)

        #expect(idleTimer.isIdleTimerDisabled == false)
    }

    @Test func externalAppearanceTracksTheController() {
        let runtime = ThrowRuntime(
            session: .fixture(),
            idleTimerController: IdleTimerControllerSpy(isIdleTimerDisabled: false),
        )
        let output = ProjectionOutput.externalDisplay(
            ProjectionOutputID(rawValue: "external-test"),
        )
        var received: [UIUserInterfaceStyle] = []

        runtime.projectionOutputConnected(output) { received.append($0) }
        runtime.controllerAppearanceDidChange(.dark)
        runtime.controllerAppearanceDidChange(.dark)
        runtime.controllerAppearanceDidChange(.light)

        #expect(received == [.unspecified, .dark, .light])
    }

    @Test func sessionOutputDemandDrivesTheIdleTimerBridge() {
        let session = ThrowSession.fixture()
        let idleTimer = IdleTimerControllerSpy(isIdleTimerDisabled: false)
        let runtime = ThrowRuntime(session: session, idleTimerController: idleTimer)
        let output = ProjectionOutput.preview(
            ProjectionOutputID(rawValue: "session-preview-test"),
        )

        session.projectionOutputConnected(output)
        runtime.sessionOutputDemandDidChange()
        #expect(idleTimer.isIdleTimerDisabled)

        session.projectionOutputDisconnected(output)
        runtime.sessionOutputDemandDidChange()
        #expect(idleTimer.isIdleTimerDisabled == false)
        #expect(idleTimer.assignedStates == [true, false])
    }

    @Test func sessionOutputDemandRestoresAnInitiallyDisabledIdleTimer() {
        let session = ThrowSession.fixture()
        let idleTimer = IdleTimerControllerSpy(isIdleTimerDisabled: true)
        let runtime = ThrowRuntime(session: session, idleTimerController: idleTimer)
        let output = ProjectionOutput.fullScreen(
            ProjectionOutputID(rawValue: "session-full-screen-test"),
        )

        session.projectionOutputConnected(output)
        runtime.sessionOutputDemandDidChange()
        #expect(idleTimer.isIdleTimerDisabled)

        session.projectionOutputDisconnected(output)
        runtime.sessionOutputDemandDidChange()
        #expect(idleTimer.isIdleTimerDisabled)
        #expect(idleTimer.assignedStates == [true, true])
    }
}
