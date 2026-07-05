@_spi(Testing) import ForemanCore
import Foundation
import Testing

@MainActor
struct WorkerSupervisorTests {
    private struct Fixture {
        let supervisor: WorkerSupervisor
        let directory: URL
        let sleep: SleepAssertionRecorder
    }

    private func makeFixture() throws -> Fixture {
        let directory = try makeTemporaryDirectory()
        let recorder = SleepAssertionRecorder()
        let supervisor = WorkerSupervisor(
            logDirectory: directory.appendingPathComponent("logs"),
            sleepInhibitor: SleepInhibitor(backend: recorder),
        )
        return Fixture(supervisor: supervisor, directory: directory, sleep: recorder)
    }

    private func makeRepo(named name: String, under base: URL) throws -> ScannedRepo {
        let root = base.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return ScannedRepo(name: name, rootURL: root)
    }

    private static let longRunningScript = """
    #!/bin/sh
    echo worker started
    while true; do sleep 0.1; done
    """

    @Test func startRunsTheWorkerAndCapturesItsOutput() async throws {
        let fixture = try makeFixture()
        let repo = try makeRepo(named: "Thing", under: fixture.directory)
        let stub = try makeStubExecutable(in: fixture.directory, script: Self.longRunningScript)

        fixture.supervisor.start(repo: repo, options: .standard, executable: stub)

        try await waitUntil("worker reaches running") {
            if case .running = fixture.supervisor.state(for: repo.id) { true } else { false }
        }
        let logURL = fixture.supervisor.logFileURL(for: repo)
        #expect(logURL.lastPathComponent == "Thing.log")
        try await waitUntil("stdout lands in the log file") {
            ((try? String(contentsOf: logURL, encoding: .utf8)) ?? "")
                .contains("worker started")
        }

        fixture.supervisor.stop(repo.id)
        try await waitUntil("worker stops") {
            fixture.supervisor.state(for: repo.id) == .stopped
        }
    }

    @Test func stopIsAStopEvenThoughSIGTERMKillsTheProcessBySignal() async throws {
        let fixture = try makeFixture()
        let repo = try makeRepo(named: "Thing", under: fixture.directory)
        let stub = try makeStubExecutable(in: fixture.directory, script: Self.longRunningScript)

        fixture.supervisor.start(repo: repo, options: .standard, executable: stub)
        try await waitUntil("worker reaches running") {
            fixture.supervisor.state(for: repo.id).isLive
        }

        fixture.supervisor.stop(repo.id)

        try await waitUntil("worker stops") {
            fixture.supervisor.state(for: repo.id) == .stopped
        }
    }

    @Test func cleanSelfExitEndsStopped() async throws {
        let fixture = try makeFixture()
        let repo = try makeRepo(named: "Thing", under: fixture.directory)
        let stub = try makeStubExecutable(
            in: fixture.directory,
            script: "#!/bin/sh\nexit 0\n",
        )

        fixture.supervisor.start(repo: repo, options: .standard, executable: stub)

        try await waitUntil("worker settles") {
            fixture.supervisor.state(for: repo.id) == .stopped
        }
    }

    @Test func nonZeroSelfExitEndsFailed() async throws {
        let fixture = try makeFixture()
        let repo = try makeRepo(named: "Thing", under: fixture.directory)
        let stub = try makeStubExecutable(
            in: fixture.directory,
            script: "#!/bin/sh\nexit 3\n",
        )

        fixture.supervisor.start(repo: repo, options: .standard, executable: stub)

        try await waitUntil("worker fails") {
            fixture.supervisor.state(for: repo.id) == .failed(reason: "Exited with code 3")
        }
    }

    @Test func missingExecutableLandsInFailedStateInsteadOfThrowing() throws {
        let fixture = try makeFixture()
        let repo = try makeRepo(named: "Thing", under: fixture.directory)
        let missing = fixture.directory.appendingPathComponent("gone")

        fixture.supervisor.start(repo: repo, options: .standard, executable: missing)

        if case .failed = fixture.supervisor.state(for: repo.id) {
        } else {
            Issue.record("Expected .failed, got \(fixture.supervisor.state(for: repo.id))")
        }
        #expect(fixture.sleep.begins == fixture.sleep.ends)
    }

    @Test func startWhileLiveIsIgnored() async throws {
        let fixture = try makeFixture()
        let repo = try makeRepo(named: "Thing", under: fixture.directory)
        let stub = try makeStubExecutable(in: fixture.directory, script: Self.longRunningScript)

        fixture.supervisor.start(repo: repo, options: .standard, executable: stub)
        try await waitUntil("worker reaches running") {
            if case .running = fixture.supervisor.state(for: repo.id) { true } else { false }
        }
        let firstState = fixture.supervisor.state(for: repo.id)

        fixture.supervisor.start(repo: repo, options: .standard, executable: stub)

        // Same pid — the second start didn't spawn a replacement.
        #expect(fixture.supervisor.state(for: repo.id) == firstState)

        fixture.supervisor.stop(repo.id)
        try await waitUntil("worker stops") {
            fixture.supervisor.state(for: repo.id) == .stopped
        }
    }

    @Test func startWhileStoppingQueuesARestart() async throws {
        let fixture = try makeFixture()
        let repo = try makeRepo(named: "Thing", under: fixture.directory)
        let stub = try makeStubExecutable(in: fixture.directory, script: Self.longRunningScript)

        fixture.supervisor.start(repo: repo, options: .standard, executable: stub)
        try await waitUntil("worker reaches running") {
            if case .running = fixture.supervisor.state(for: repo.id) { true } else { false }
        }
        let firstPid = try #require(pid(of: fixture.supervisor.state(for: repo.id)))

        // The user's off-then-on flip, before the old process has exited.
        fixture.supervisor.stop(repo.id)
        #expect(fixture.supervisor.state(for: repo.id) == .stopping(restartPending: false))
        fixture.supervisor.start(repo: repo, options: .standard, executable: stub)
        #expect(fixture.supervisor.state(for: repo.id) == .stopping(restartPending: true))

        try await waitUntil("replacement worker reaches running") {
            if case .running = fixture.supervisor.state(for: repo.id) { true } else { false }
        }
        let secondPid = try #require(pid(of: fixture.supervisor.state(for: repo.id)))
        #expect(secondPid != firstPid)

        fixture.supervisor.stop(repo.id)
        try await waitUntil("worker stops") {
            fixture.supervisor.state(for: repo.id) == .stopped
        }
    }

    @Test func stopWhileARestartIsPendingCancelsIt() async throws {
        let fixture = try makeFixture()
        let repo = try makeRepo(named: "Thing", under: fixture.directory)
        let stub = try makeStubExecutable(in: fixture.directory, script: Self.longRunningScript)

        fixture.supervisor.start(repo: repo, options: .standard, executable: stub)
        try await waitUntil("worker reaches running") {
            fixture.supervisor.state(for: repo.id).isLive
        }

        fixture.supervisor.stop(repo.id)
        fixture.supervisor.start(repo: repo, options: .standard, executable: stub)
        fixture.supervisor.stop(repo.id)
        #expect(fixture.supervisor.state(for: repo.id) == .stopping(restartPending: false))

        // With the restart cancelled the exit must settle at .stopped; a
        // leaked pending start would resolve to .running and time out here.
        try await waitUntil("worker settles at stopped") {
            fixture.supervisor.state(for: repo.id) == .stopped
        }
    }

    private func pid(of state: WorkerSupervisor.WorkerState) -> Int32? {
        if case let .running(pid, _) = state { pid } else { nil }
    }

    @Test func runningStateCarriesTheSpawnTime() async throws {
        let fixture = try makeFixture()
        let repo = try makeRepo(named: "Thing", under: fixture.directory)
        let stub = try makeStubExecutable(in: fixture.directory, script: Self.longRunningScript)
        let before = Date()

        fixture.supervisor.start(repo: repo, options: .standard, executable: stub)
        try await waitUntil("worker reaches running") {
            if case .running = fixture.supervisor.state(for: repo.id) { true } else { false }
        }

        guard case let .running(_, since) = fixture.supervisor.state(for: repo.id) else {
            Issue.record("Expected a running state")
            return
        }
        #expect(since >= before)
        #expect(since <= Date())

        fixture.supervisor.stop(repo.id)
        try await waitUntil("worker stops") {
            fixture.supervisor.state(for: repo.id) == .stopped
        }
    }

    @Test func recordStartFailureReadsAsFailed() throws {
        let fixture = try makeFixture()
        let repo = try makeRepo(named: "Thing", under: fixture.directory)

        fixture.supervisor.recordStartFailure(repo.id, reason: "cursor-agent was not found")

        #expect(
            fixture.supervisor.state(for: repo.id)
                == .failed(reason: "cursor-agent was not found"),
        )
    }

    @Test func recordStartFailureWhileLiveIsIgnored() async throws {
        let fixture = try makeFixture()
        let repo = try makeRepo(named: "Thing", under: fixture.directory)
        let stub = try makeStubExecutable(in: fixture.directory, script: Self.longRunningScript)

        fixture.supervisor.start(repo: repo, options: .standard, executable: stub)
        try await waitUntil("worker reaches running") {
            if case .running = fixture.supervisor.state(for: repo.id) { true } else { false }
        }
        let runningState = fixture.supervisor.state(for: repo.id)

        fixture.supervisor.recordStartFailure(repo.id, reason: "should not apply")

        #expect(fixture.supervisor.state(for: repo.id) == runningState)

        fixture.supervisor.stop(repo.id)
        try await waitUntil("worker stops") {
            fixture.supervisor.state(for: repo.id) == .stopped
        }
    }

    @Test func stopAllStopsEveryWorkerAndReleasesTheSleepAssertionOnce() async throws {
        let fixture = try makeFixture()
        let first = try makeRepo(named: "First", under: fixture.directory)
        let second = try makeRepo(named: "Second", under: fixture.directory)
        let stub = try makeStubExecutable(in: fixture.directory, script: Self.longRunningScript)

        fixture.supervisor.start(repo: first, options: .standard, executable: stub)
        fixture.supervisor.start(repo: second, options: .standard, executable: stub)
        try await waitUntil("both workers reach running") {
            fixture.supervisor.state(for: first.id).isLive
                && fixture.supervisor.state(for: second.id).isLive
        }

        // One assertion covers all live workers; the second start doesn't
        // re-take it.
        #expect(fixture.sleep.begins == 1)
        #expect(fixture.supervisor.isInhibitingSleep)

        fixture.supervisor.stopAll()

        try await waitUntil("both workers stop") {
            fixture.supervisor.state(for: first.id) == .stopped
                && fixture.supervisor.state(for: second.id) == .stopped
        }
        #expect(fixture.sleep.ends == 1)
        #expect(!fixture.supervisor.isInhibitingSleep)
    }
}
