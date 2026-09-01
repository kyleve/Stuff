import Testing
@testable import Throw
@_spi(Testing) @testable import ThrowUI
import UIKit

@MainActor
struct ThrowRuntimeTests {
    @Test func controllerSceneCancellationCannotCancelTheProcessLaunch() async {
        let harness = ThrowSessionLaunchTestHarness.configuredSuspended()
        let session = harness.session
        let runtime = ThrowRuntime(
            session: session,
            idleTimerController: IdleTimerControllerSpy(isIdleTimerDisabled: false),
            backgroundExecutionLeaser: BackgroundExecutionLeaserSpy(),
        )
        let first = ControllerSceneID(rawValue: "launch-first")
        let second = ControllerSceneID(rawValue: "launch-second")

        await harness.waitForLoadToStart()
        runtime.controllerScene(first, didReceive: .willEnterForeground)
        runtime.controllerScene(second, didReceive: .willEnterForeground)
        let sceneWaiter = Task(name: "Throw cancelled scene launch waiter") {
            await session.waitForLaunchForTesting()
        }
        sceneWaiter.cancel()
        runtime.controllerScene(first, didReceive: .didDisconnect)
        runtime.controllerScene(second, didReceive: .didEnterBackground)

        let loadCountBeforeResume = await harness.loadCallCount()
        #expect(loadCountBeforeResume == 1)
        await harness.resumeLoad()
        await session.waitForLaunchForTesting()
        await sceneWaiter.value

        guard case .ready = session.launchState else {
            Issue.record("Scene cancellation must not cancel the process launch")
            return
        }
        let finalLoadCount = await harness.loadCallCount()
        #expect(finalLoadCount == 1)
        #expect(session.hasForegroundControllerSceneForTesting == false)
    }

    @Test func firstAndLastOutputOwnIdleTimerRestoration() {
        let idleTimer = IdleTimerControllerSpy(isIdleTimerDisabled: false)
        let runtime = ThrowRuntime(
            session: .fixture(),
            idleTimerController: idleTimer,
            backgroundExecutionLeaser: BackgroundExecutionLeaserSpy(),
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
            backgroundExecutionLeaser: BackgroundExecutionLeaserSpy(),
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
            backgroundExecutionLeaser: BackgroundExecutionLeaserSpy(),
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
        let runtime = ThrowRuntime(
            session: session,
            idleTimerController: idleTimer,
            backgroundExecutionLeaser: BackgroundExecutionLeaserSpy(),
        )
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
        let runtime = ThrowRuntime(
            session: session,
            idleTimerController: idleTimer,
            backgroundExecutionLeaser: BackgroundExecutionLeaserSpy(),
        )
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

    @Test func twoControllerScenesOwnAggregateForegroundPresence() {
        let session = ThrowSession.fixture()
        let idleTimer = IdleTimerControllerSpy(isIdleTimerDisabled: false)
        let runtime = ThrowRuntime(
            session: session,
            idleTimerController: idleTimer,
            backgroundExecutionLeaser: BackgroundExecutionLeaserSpy(),
        )
        let firstController = ControllerSceneID(rawValue: "controller-first")
        let secondController = ControllerSceneID(rawValue: "controller-second")
        let externalOutput = ProjectionOutput.externalDisplay(
            ProjectionOutputID(rawValue: "external-lifecycle-test"),
        )

        runtime.projectionOutputConnected(externalOutput) { _ in }
        #expect(session.hasProjectionOutputDemand)
        #expect(session.hasForegroundControllerSceneForTesting == false)

        runtime.controllerScene(firstController, didReceive: .willEnterForeground)
        runtime.controllerScene(secondController, didReceive: .willEnterForeground)
        runtime.controllerScene(firstController, didReceive: .didEnterBackground)
        #expect(session.hasForegroundControllerSceneForTesting)

        runtime.controllerScene(secondController, didReceive: .didDisconnect)
        #expect(session.hasForegroundControllerSceneForTesting == false)
        #expect(session.hasProjectionOutputDemand)

        runtime.controllerScene(firstController, didReceive: .willEnterForeground)
        #expect(session.hasForegroundControllerSceneForTesting)

        runtime.controllerScene(firstController, didReceive: .didDisconnect)
        runtime.projectionOutputDisconnected(externalOutput)
        #expect(session.hasForegroundControllerSceneForTesting == false)
        #expect(session.hasProjectionOutputDemand == false)
        #expect(idleTimer.assignedStates == [true, false])
    }

    @Test func finalControllerBackgroundEndsItsPersistenceLeaseAfterFlush() async throws {
        let session = ThrowSession.fixture()
        let leaser = BackgroundExecutionLeaserSpy()
        let runtime = ThrowRuntime(
            session: session,
            idleTimerController: IdleTimerControllerSpy(isIdleTimerDisabled: false),
            backgroundExecutionLeaser: leaser,
        )
        let controller = ControllerSceneID(rawValue: "controller-background-flush")
        runtime.controllerScene(controller, didReceive: .willEnterForeground)
        #expect(session.beginPreferenceMutation())

        runtime.controllerScene(controller, didReceive: .didEnterBackground)

        let lease = try #require(leaser.lastLease)
        #expect(leaser.beginCallCount == 1)
        while session.preferencePersistence.quiescenceWaiterCount == 0,
              lease.endCallCount == 0
        {
            await Task.yield()
        }
        #expect(session.preferencePersistence.quiescenceWaiterCount == 1)
        #expect(lease.endCallCount == 0)
        session.finishPreferenceMutation()
        await lease.waitForEndCallCount(1)
        #expect(lease.endCallCount == 1)
    }

    @Test func backgroundPersistenceExpirationCancelsAndEndsItsLeaseOnce() async throws {
        let session = ThrowSession.fixture()
        let leaser = BackgroundExecutionLeaserSpy()
        let runtime = ThrowRuntime(
            session: session,
            idleTimerController: IdleTimerControllerSpy(isIdleTimerDisabled: false),
            backgroundExecutionLeaser: leaser,
        )
        let controller = ControllerSceneID(rawValue: "controller-expired-flush")
        runtime.controllerScene(controller, didReceive: .willEnterForeground)
        #expect(session.beginPreferenceMutation())
        runtime.controllerScene(controller, didReceive: .didEnterBackground)
        let lease = try #require(leaser.lastLease)
        while session.preferencePersistence.quiescenceWaiterCount == 0,
              lease.endCallCount == 0
        {
            await Task.yield()
        }
        #expect(session.preferencePersistence.quiescenceWaiterCount == 1)
        #expect(lease.endCallCount == 0)

        leaser.expire()

        #expect(lease.endCallCount == 1)
        session.finishPreferenceMutation()
        await session.flushPreferencesSave()
        await Task.yield()
        #expect(lease.endCallCount == 1)
    }
}
