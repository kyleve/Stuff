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

        await runner.teardown(LifecycleSteps {
            LifecycleStep.work("teardown") { _ in events.append("teardown") }
        })
        #expect(events == ["launch", "teardown", "launch"])
        #expect(runner.phase.isReady)
    }

    @Test func resetRunsTeardownStepsInOrder() async {
        var events: [String] = []
        let runner = LifecycleRunner(reason: .userForeground, sequence: LifecycleSteps {})
        await runner.run()

        await runner.teardown(LifecycleSteps {
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
            await runner.teardown(LifecycleSteps {
                LifecycleStep.interactive("signing-out") { _ in Text("Signing out") }
            })
        }
        try await waitUntil { runner.phase.isRunning("signing-out") }
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

        await runner.teardown(LifecycleSteps {
            LifecycleStep.work("teardown") { _ in throw ResetError() }
        })
        #expect(runner.phase.failed(at: "teardown"))
        #expect(!relaunched)
    }

    @Test func retryAfterFailedTeardownReRunsTeardownThenRelaunches() async throws {
        var events: [String] = []
        var shouldFailErase = true
        let runner = LifecycleRunner(reason: .userForeground, sequence: LifecycleSteps {
            LifecycleStep.work("launch") { _ in events.append("launch") }
        })
        await runner.run()
        events.removeAll()

        await runner.teardown(LifecycleSteps {
            LifecycleStep.work("erase") { _ in
                events.append("erase")
                if shouldFailErase { throw ResetError() }
            }
            LifecycleStep.work("clear-prefs") { _ in events.append("clear-prefs") }
        })
        #expect(runner.phase.failed(at: "erase"))
        #expect(events == ["erase"])

        // Retry must resume the teardown (re-erasing) and only then relaunch —
        // not silently re-drive the launch sequence over un-torn-down state.
        shouldFailErase = false
        events.removeAll()
        runner.retry()
        try await waitUntil { runner.phase.isReady }
        #expect(events == ["erase", "clear-prefs", "launch"])
    }

    @Test func retryAfterFailedTeardownTailResumesWithoutReErasing() async throws {
        var events: [String] = []
        var shouldFailPrefs = true
        let runner = LifecycleRunner(reason: .userForeground, sequence: LifecycleSteps {
            LifecycleStep.work("launch") { _ in events.append("launch") }
        })
        await runner.run()
        events.removeAll()

        await runner.teardown(LifecycleSteps {
            LifecycleStep.work("erase") { _ in events.append("erase") }
            LifecycleStep.work("clear-prefs") { _ in
                events.append("clear-prefs")
                if shouldFailPrefs { throw ResetError() }
            }
        })
        #expect(runner.phase.failed(at: "clear-prefs"))
        #expect(events == ["erase", "clear-prefs"])

        // The earlier teardown step ("erase") already succeeded, so retry resumes
        // from the failed step rather than re-running it, then relaunches.
        shouldFailPrefs = false
        events.removeAll()
        runner.retry()
        try await waitUntil { runner.phase.isReady }
        #expect(events == ["clear-prefs", "launch"])
    }
}
