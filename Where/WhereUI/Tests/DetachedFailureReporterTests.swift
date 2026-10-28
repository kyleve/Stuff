import Foundation
import LifecycleKit
import Testing
@testable import WhereUI

private struct FanError: Error {}

private struct WaitTimeout: Error {}

/// Polls `predicate` on the main actor until it holds or the timeout elapses,
/// yielding to the observation re-arm hop between checks.
@MainActor
private func waitUntil(
    timeout: Duration = .seconds(5),
    _ predicate: () -> Bool,
) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !predicate() {
        if ContinuousClock.now >= deadline { throw WaitTimeout() }
        try await Task.sleep(for: .milliseconds(1))
    }
}

/// A minimal typed root so a reporter test can drive a real runner without
/// Where's services.
private struct RootStep: LifecycleStep {
    let id = "root"

    func run(_: Void, _: LifecycleStepContext) async throws -> String {
        "value"
    }
}

/// A detached child that always throws, landing on `detachedFailures`.
private struct ThrowingChildStep: LifecycleStep {
    let id: String

    func run(_: String, _: LifecycleStepContext) async throws {
        throw FanError()
    }
}

@MainActor
struct DetachedFailureReporterTests {
    private func failure(_ id: String) -> LifecycleFailure {
        LifecycleFailure(stepID: id, error: FanError())
    }

    @Test func reportsOnlyTheNewEntriesExactlyOnce() {
        let reporter = DetachedFailureReporter()

        let first = reporter.report([failure("a")])
        #expect(first.map { "\($0.stepID)" } == ["a"])

        // Re-reporting the same array adds nothing; growing it reports only
        // the tail.
        #expect(reporter.report([failure("a")]).isEmpty)
        let second = reporter.report([failure("a"), failure("b")])
        #expect(second.map { "\($0.stepID)" } == ["b"])
        #expect(reporter.reportedTotal == 2)
    }

    @Test func restartsAfterTheRunnerClearsForAFreshAttempt() {
        // The runner empties `detachedFailures` when a fresh attempt begins
        // (first run, post-teardown relaunch); a shrink restarts reporting so
        // the next attempt's failures aren't misread as already seen.
        let reporter = DetachedFailureReporter()
        reporter.report([failure("a"), failure("b")])

        #expect(reporter.report([]).isEmpty)
        let next = reporter.report([failure("c")])
        #expect(next.map { "\($0.stepID)" } == ["c"])
        #expect(reporter.reportedTotal == 3)
    }

    @Test func observingALiveRunnerReportsFailuresAsTheyLand() async throws {
        // End-to-end plumbing: a runner whose detached fan throws must reach
        // the reporter through the observation chain — no view tree involved,
        // matching the headless-launch case the reporter exists for.
        let runner = LifecycleRunner(
            reason: .userForeground,
            plan: LaunchPlan(RootStep())
                .detached {
                    ThrowingChildStep(id: "boom-1")
                    ThrowingChildStep(id: "boom-2")
                },
        )
        let reporter = DetachedFailureReporter()
        reporter.observe(runner)

        await runner.run()
        #expect(runner.phase.isReady)
        #expect(runner.detachedFailures.count == 2)

        // The onChange → re-arm hop is asynchronous; wait for the reports to
        // drain rather than assuming a fixed number of run-loop turns.
        try await waitUntil { reporter.reportedTotal == 2 }
    }
}
