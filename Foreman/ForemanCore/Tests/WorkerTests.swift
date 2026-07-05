@_spi(Testing) import ForemanCore
import Foundation
import Testing

@MainActor
struct WorkerTests {
    /// Counts state transitions so tests can assert the change hook fires
    /// exactly once per transition.
    @MainActor
    private final class ChangeCounter {
        var changes = 0
    }

    private struct Fixture {
        let worker: Worker
        let directory: URL
        let changes: ChangeCounter
    }

    private func makeFixture(named name: String = "Thing") throws -> Fixture {
        let directory = try makeTemporaryDirectory()
        let root = directory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let counter = ChangeCounter()
        let worker = Worker(
            name: name,
            workerDirectory: root,
            logDirectory: directory.appendingPathComponent("logs"),
            onStateChange: { counter.changes += 1 },
        )
        return Fixture(worker: worker, directory: directory, changes: counter)
    }

    private static let longRunningScript = """
    #!/bin/sh
    echo worker started
    while true; do sleep 0.1; done
    """

    @Test func startRunsTheWorkerAndCapturesItsOutput() async throws {
        let fixture = try makeFixture()
        let stub = try makeStubExecutable(in: fixture.directory, script: Self.longRunningScript)

        fixture.worker.start(options: .standard, executable: stub)

        try await waitUntil("worker reaches running") {
            if case .running = fixture.worker.state { true } else { false }
        }
        #expect(fixture.worker.logFileURL.lastPathComponent == "Thing.log")
        try await waitUntil("stdout lands in the log file") {
            ((try? String(contentsOf: fixture.worker.logFileURL, encoding: .utf8)) ?? "")
                .contains("worker started")
        }

        fixture.worker.stop()
        try await waitUntil("worker stops") {
            fixture.worker.state == .stopped
        }
    }

    @Test func stopIsAStopEvenThoughSIGTERMKillsTheProcessBySignal() async throws {
        let fixture = try makeFixture()
        let stub = try makeStubExecutable(in: fixture.directory, script: Self.longRunningScript)

        fixture.worker.start(options: .standard, executable: stub)
        try await waitUntil("worker reaches running") {
            fixture.worker.state.isLive
        }

        fixture.worker.stop()

        try await waitUntil("worker stops") {
            fixture.worker.state == .stopped
        }
    }

    @Test func cleanSelfExitEndsStopped() async throws {
        let fixture = try makeFixture()
        let stub = try makeStubExecutable(
            in: fixture.directory,
            script: "#!/bin/sh\nexit 0\n",
        )

        fixture.worker.start(options: .standard, executable: stub)

        try await waitUntil("worker settles") {
            fixture.worker.state == .stopped
        }
    }

    @Test func nonZeroSelfExitEndsFailed() async throws {
        let fixture = try makeFixture()
        let stub = try makeStubExecutable(
            in: fixture.directory,
            script: "#!/bin/sh\nexit 3\n",
        )

        fixture.worker.start(options: .standard, executable: stub)

        try await waitUntil("worker fails") {
            fixture.worker.state == .failed(reason: "Exited with code 3")
        }
    }

    @Test func missingExecutableLandsInFailedStateInsteadOfThrowing() throws {
        let fixture = try makeFixture()
        let missing = fixture.directory.appendingPathComponent("gone")

        fixture.worker.start(options: .standard, executable: missing)

        if case .failed = fixture.worker.state {
        } else {
            Issue.record("Expected .failed, got \(fixture.worker.state)")
        }
    }

    @Test func startWhileLiveIsIgnored() async throws {
        let fixture = try makeFixture()
        let stub = try makeStubExecutable(in: fixture.directory, script: Self.longRunningScript)

        fixture.worker.start(options: .standard, executable: stub)
        try await waitUntil("worker reaches running") {
            if case .running = fixture.worker.state { true } else { false }
        }
        let firstState = fixture.worker.state

        fixture.worker.start(options: .standard, executable: stub)

        // Same pid — the second start didn't spawn a replacement.
        #expect(fixture.worker.state == firstState)

        fixture.worker.stop()
        try await waitUntil("worker stops") {
            fixture.worker.state == .stopped
        }
    }

    @Test func startWhileStoppingQueuesARestart() async throws {
        let fixture = try makeFixture()
        let stub = try makeStubExecutable(in: fixture.directory, script: Self.longRunningScript)

        fixture.worker.start(options: .standard, executable: stub)
        try await waitUntil("worker reaches running") {
            if case .running = fixture.worker.state { true } else { false }
        }
        let firstPid = try #require(pid(of: fixture.worker.state))

        // The user's off-then-on flip, before the old process has exited.
        fixture.worker.stop()
        #expect(fixture.worker.state == .stopping(restartPending: false))
        fixture.worker.start(options: .standard, executable: stub)
        #expect(fixture.worker.state == .stopping(restartPending: true))

        try await waitUntil("replacement worker reaches running") {
            if case .running = fixture.worker.state { true } else { false }
        }
        let secondPid = try #require(pid(of: fixture.worker.state))
        #expect(secondPid != firstPid)

        fixture.worker.stop()
        try await waitUntil("worker stops") {
            fixture.worker.state == .stopped
        }
    }

    @Test func stopWhileARestartIsPendingCancelsIt() async throws {
        let fixture = try makeFixture()
        let stub = try makeStubExecutable(in: fixture.directory, script: Self.longRunningScript)

        fixture.worker.start(options: .standard, executable: stub)
        try await waitUntil("worker reaches running") {
            fixture.worker.state.isLive
        }

        fixture.worker.stop()
        fixture.worker.start(options: .standard, executable: stub)
        fixture.worker.stop()
        #expect(fixture.worker.state == .stopping(restartPending: false))

        // With the restart cancelled the exit must settle at .stopped; a
        // leaked pending start would resolve to .running and time out here.
        try await waitUntil("worker settles at stopped") {
            fixture.worker.state == .stopped
        }
    }

    @Test func runningStateCarriesTheSpawnTime() async throws {
        let fixture = try makeFixture()
        let stub = try makeStubExecutable(in: fixture.directory, script: Self.longRunningScript)
        let before = Date()

        fixture.worker.start(options: .standard, executable: stub)
        try await waitUntil("worker reaches running") {
            if case .running = fixture.worker.state { true } else { false }
        }

        guard case let .running(_, since) = fixture.worker.state else {
            Issue.record("Expected a running state")
            return
        }
        #expect(since >= before)
        #expect(since <= Date())

        fixture.worker.stop()
        try await waitUntil("worker stops") {
            fixture.worker.state == .stopped
        }
    }

    @Test func recordStartFailureReadsAsFailed() throws {
        let fixture = try makeFixture()

        fixture.worker.recordStartFailure(reason: "cursor-agent was not found")

        #expect(fixture.worker.state == .failed(reason: "cursor-agent was not found"))
    }

    @Test func recordStartFailureWhileLiveIsIgnored() async throws {
        let fixture = try makeFixture()
        let stub = try makeStubExecutable(in: fixture.directory, script: Self.longRunningScript)

        fixture.worker.start(options: .standard, executable: stub)
        try await waitUntil("worker reaches running") {
            if case .running = fixture.worker.state { true } else { false }
        }
        let runningState = fixture.worker.state

        fixture.worker.recordStartFailure(reason: "should not apply")

        #expect(fixture.worker.state == runningState)

        fixture.worker.stop()
        try await waitUntil("worker stops") {
            fixture.worker.state == .stopped
        }
    }

    @Test func onStateChangeFiresOncePerTransitionAndSkipsSameValueWrites() throws {
        let fixture = try makeFixture()

        fixture.worker.recordStartFailure(reason: "no agent")
        #expect(fixture.changes.changes == 1)

        // Same failure again: the state value is unchanged, so no callback.
        fixture.worker.recordStartFailure(reason: "no agent")
        #expect(fixture.changes.changes == 1)

        // A different reason is a real transition.
        fixture.worker.recordStartFailure(reason: "still no agent")
        #expect(fixture.changes.changes == 2)
    }

    private func pid(of state: Worker.State) -> Int32? {
        if case let .running(pid, _) = state { pid } else { nil }
    }
}
