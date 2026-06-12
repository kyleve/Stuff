@testable import LifecycleKit
import SwiftUI
import Testing

private struct StepError: Error {}

/// Polls `condition` on the main actor until it holds or the timeout elapses.
/// Sleeping yields to the launcher's drive task between checks.
@MainActor
func waitUntil(
    timeout: Duration = .seconds(2),
    _ condition: () -> Bool,
) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !condition() {
        if ContinuousClock.now >= deadline {
            throw StepError()
        }
        try await Task.sleep(for: .milliseconds(1))
    }
}

@MainActor
struct LauncherDriveTests {
    @Test func runsStepsInDeclarationOrder() async {
        var executed: [String] = []
        let launcher = Launcher(reason: .userForeground, sequence: LaunchSequence {
            Work("a") { _ in executed.append("a") }
            Work("b") { _ in executed.append("b") }
            Work("c") { _ in executed.append("c") }
        })
        await launcher.run()
        #expect(executed == ["a", "b", "c"])
        #expect(launcher.phase.isReady)
    }

    @Test func skipsStepsWhoseConditionIsFalse() async {
        var executed: [String] = []
        let launcher = Launcher(reason: .userForeground, sequence: LaunchSequence {
            Work("a") { _ in executed.append("a") }
            Work("skip") { _ in executed.append("skip") }.when { false }
            Work("c") { _ in executed.append("c") }
        })
        await launcher.run()
        #expect(executed == ["a", "c"])
    }

    @Test func filtersStepsByLaunchReason() async {
        var executed: [String] = []
        let launcher = Launcher(reason: .background(.location), sequence: LaunchSequence {
            Work("always") { _ in executed.append("always") }
            Work("fg") { _ in executed.append("fg") }.modes(.foreground)
            Work("bg") { _ in executed.append("bg") }.modes(.background)
        })
        await launcher.run()
        #expect(executed == ["always", "bg"])
    }

    @Test func interactiveStepsAreSkippedInBackground() async {
        var executed: [String] = []
        let launcher = Launcher(reason: .background(.location), sequence: LaunchSequence {
            Work("a") { _ in executed.append("a") }
            Interactive("onboarding", run: { _ in executed.append("onboarding") }) { _ in
                Text("onboarding")
            }
            Work("c") { _ in executed.append("c") }
        })
        await launcher.run()
        #expect(executed == ["a", "c"])
        #expect(launcher.phase.isReady)
    }

    @Test func runIsIdempotent() async {
        var count = 0
        let launcher = Launcher(reason: .userForeground, sequence: LaunchSequence {
            Work("a") { _ in count += 1 }
        })
        await launcher.run()
        await launcher.run()
        #expect(count == 1)
    }
}

@MainActor
struct LauncherFailureTests {
    @Test func thrownErrorParksInFailedAndStopsSubsequentSteps() async {
        var executed: [String] = []
        let launcher = Launcher(reason: .userForeground, sequence: LaunchSequence {
            Work("a") { _ in executed.append("a") }
            Work("b") { _ in throw StepError() }
            Work("c") { _ in executed.append("c") }
        })
        await launcher.run()
        #expect(executed == ["a"])
        #expect(launcher.phase.failure?.stepID == "b")
        #expect(launcher.phase.failure?.error is StepError)
    }

    @Test func retryResumesFromFailedStep() async throws {
        var executed: [String] = []
        var shouldFail = true
        let launcher = Launcher(reason: .userForeground, sequence: LaunchSequence {
            Work("a") { _ in executed.append("a") }
            Work("b") { _ in
                if shouldFail { throw StepError() }
                executed.append("b")
            }
            Work("c") { _ in executed.append("c") }
        })
        await launcher.run()
        #expect(launcher.phase.failure?.stepID == "b")
        #expect(executed == ["a"])

        shouldFail = false
        launcher.retry()
        try await waitUntil { launcher.phase.isReady }
        #expect(executed == ["a", "b", "c"])
    }

    @Test func retryIsNoOpWhenNotFailed() async {
        let launcher = Launcher(reason: .userForeground, sequence: LaunchSequence {
            Work("a") { _ in }
        })
        await launcher.run()
        launcher.retry()
        #expect(launcher.phase.isReady)
    }

    @Test func handleFailurePropagatesToFailedPhase() async throws {
        let launcher = Launcher(reason: .userForeground, sequence: LaunchSequence {
            Interactive("gate") { _ in Text("x") }
        })
        let task = Task { @MainActor in await launcher.run() }
        try await waitUntil { launcher.phase.runningStepID == "gate" }
        launcher.phase.runningHandle?.fail(StepError())
        await task.value
        #expect(launcher.phase.failure?.stepID == "gate")
    }
}

@MainActor
struct LauncherInteractiveTests {
    @Test func interactiveStepSuspendsUntilResolved() async throws {
        var executed: [String] = []
        let launcher = Launcher(reason: .userForeground, sequence: LaunchSequence {
            Work("a") { _ in executed.append("a") }
            Interactive("gate") { _ in Text("gate") }
            Work("c") { _ in executed.append("c") }
        })
        let task = Task { @MainActor in await launcher.run() }
        try await waitUntil { launcher.phase.runningStepID == "gate" }
        #expect(executed == ["a"])
        #expect(!launcher.phase.isReady)

        launcher.phase.runningHandle?.complete()
        await task.value
        #expect(executed == ["a", "c"])
        #expect(launcher.phase.isReady)
    }

    @Test func alwaysPresentationActivatesImmediately() async throws {
        let launcher = Launcher(reason: .userForeground, sequence: LaunchSequence {
            Interactive("ui") { _ in Text("ui") }
        })
        let task = Task { @MainActor in await launcher.run() }
        try await waitUntil { launcher.phase.runningStepID == "ui" }
        #expect(launcher.phase.runningHandle?.presentation != nil)
        launcher.phase.runningHandle?.complete()
        await task.value
    }

    @Test func whenFalsePresentationStaysSilent() async throws {
        let launcher = Launcher(reason: .userForeground, sequence: LaunchSequence {
            Work("s") { handle in try await handle.waitForResolution() }
                .presenting(when: { false }) { _ in Text("x") }
        })
        let task = Task { @MainActor in await launcher.run() }
        try await waitUntil { launcher.phase.runningStepID == "s" }
        #expect(launcher.phase.runningHandle?.presentation == nil)
        launcher.phase.runningHandle?.complete()
        await task.value
    }

    @Test func deferredPresentationActivatesAfterDelay() async throws {
        let launcher = Launcher(reason: .userForeground, sequence: LaunchSequence {
            Work("slow") { handle in try await handle.waitForResolution() }
                .presenting(after: .milliseconds(20)) { _ in Text("x") }
        })
        let task = Task { @MainActor in await launcher.run() }
        try await waitUntil { launcher.phase.runningStepID == "slow" }
        try await waitUntil { launcher.phase.runningHandle?.presentation != nil }
        launcher.phase.runningHandle?.complete()
        await task.value
    }

    @Test func progressIsReadableWhileStepRuns() async throws {
        let launcher = Launcher(reason: .userForeground, sequence: LaunchSequence {
            Interactive("p", run: { handle in
                handle.progress = 0.5
                try await handle.waitForResolution()
            }) { _ in Text("p") }
        })
        let task = Task { @MainActor in await launcher.run() }
        try await waitUntil { launcher.phase.runningStepID == "p" }
        #expect(launcher.phase.runningHandle?.progress == 0.5)
        launcher.phase.runningHandle?.complete()
        await task.value
    }
}
