@_spi(Testing) import ForemanCore
import Foundation
import Testing

@MainActor
struct WorkerSupervisorTests {
    /// Counts sleep-assertion transitions so tests never take a real one.
    @MainActor
    private final class SleepCounter {
        var begins = 0
        var ends = 0
    }

    private struct Fixture {
        let supervisor: WorkerSupervisor
        let directory: URL
        let sleep: SleepCounter
    }

    private func makeFixture() throws -> Fixture {
        let directory = try makeTemporaryDirectory()
        let counter = SleepCounter()
        let supervisor = WorkerSupervisor(
            logDirectory: directory.appendingPathComponent("logs"),
            sleepInhibitor: SleepInhibitor(
                onBegin: { counter.begins += 1 },
                onEnd: { counter.ends += 1 },
            ),
        )
        return Fixture(supervisor: supervisor, directory: directory, sleep: counter)
    }

    private func makeRepo(named name: String, under base: URL) throws -> Repo {
        let root = base.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return Repo(name: name, rootURL: root)
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
