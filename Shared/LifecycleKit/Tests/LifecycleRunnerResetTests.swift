@testable import LifecycleKit
import SwiftUI
import Testing

private struct ResetError: Error {}

@MainActor
struct LifecycleRunnerResetTests {
    @Test func resetRunsTeardownThenRelaunches() async {
        var events: [String] = []
        let runner = LifecycleRunner(reason: .userForeground, sequence: LifecycleSteps {
            LifecycleStep.work("launch") { _ in events.append("launch") }
        })
        await runner.run()
        #expect(events == ["launch"])
        #expect(runner.phase.isReady)

        await runner.reset(LifecycleSteps {
            LifecycleStep.work("teardown") { _ in events.append("teardown") }
        })
        #expect(events == ["launch", "teardown", "launch"])
        #expect(runner.phase.isReady)
    }

    @Test func resetRunsTeardownStepsInOrder() async {
        var events: [String] = []
        let runner = LifecycleRunner(reason: .userForeground, sequence: LifecycleSteps {})
        await runner.run()

        await runner.reset(LifecycleSteps {
            LifecycleStep.work("stop-gps") { _ in events.append("stop-gps") }
            LifecycleStep.work("clear-store") { _ in events.append("clear-store") }
            LifecycleStep.work("clear-widget") { _ in events.append("clear-widget") }
        })
        #expect(events == ["stop-gps", "clear-store", "clear-widget"])
    }

    @Test func resetStepCanPresentTeardownUI() async throws {
        let runner = LifecycleRunner(reason: .userForeground, sequence: LifecycleSteps {})
        await runner.run()

        let task = Task { @MainActor in
            await runner.reset(LifecycleSteps {
                LifecycleStep.interactive("signing-out") { _ in Text("Signing out") }
            })
        }
        try await waitUntil { runner.phase.runningStepID == "signing-out" }
        #expect(runner.phase.runningBridge?.presentation != nil)

        runner.phase.runningBridge?.complete()
        await task.value
        #expect(runner.phase.isReady)
    }

    @Test func failedTeardownParksInFailedAndSkipsRelaunch() async {
        var relaunched = false
        let runner = LifecycleRunner(reason: .userForeground, sequence: LifecycleSteps {
            LifecycleStep.work("launch") { _ in relaunched = true }
        })
        await runner.run()
        relaunched = false

        await runner.reset(LifecycleSteps {
            LifecycleStep.work("teardown") { _ in throw ResetError() }
        })
        #expect(runner.phase.failure?.stepID == "teardown")
        #expect(!relaunched)
    }
}
