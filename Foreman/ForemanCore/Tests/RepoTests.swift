@_spi(Testing) import ForemanCore
import Foundation
import Testing

@MainActor
struct RepoTests {
    /// Mutable executable resolution + persistence counting for one repo.
    @MainActor
    private final class Fixture {
        let directory: URL
        var executable: Result<URL, any Error>
        var persistedChanges = 0
        private(set) lazy var repo: Repo = {
            let scanned = ScannedRepo(
                name: "Thing",
                rootURL: directory.appendingPathComponent("Thing", isDirectory: true),
            )
            return Repo(
                scanned: scanned,
                isEnabled: false,
                options: .standard,
                worker: Worker(
                    name: scanned.name,
                    workerDirectory: scanned.rootURL,
                    logDirectory: directory.appendingPathComponent("logs"),
                    onStateChange: {},
                ),
                resolveExecutable: { [unowned self] in try executable.get() },
                onPersistentChange: { [unowned self] _ in persistedChanges += 1 },
            )
        }()

        init(directory: URL, executable: URL) {
            self.directory = directory
            self.executable = .success(executable)
        }
    }

    private struct LocateFailure: Error, LocalizedError {
        var errorDescription: String? {
            "cursor-agent was not found"
        }
    }

    private func makeFixture() throws -> Fixture {
        let directory = try makeTemporaryDirectory()
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("Thing", isDirectory: true),
            withIntermediateDirectories: true,
        )
        let stub = try makeStubExecutable(
            in: directory,
            script: "#!/bin/sh\nwhile true; do sleep 0.1; done\n",
        )
        return Fixture(directory: directory, executable: stub)
    }

    private func pid(of state: Worker.State) -> Int32? {
        if case let .running(pid, _) = state { pid } else { nil }
    }

    // MARK: - Enable toggle

    @Test func enablingStartsAndDisablingStopsTheWorker() async throws {
        let fixture = try makeFixture()

        fixture.repo.isEnabled = true
        try await waitUntil("worker reaches running") {
            fixture.repo.worker.state.isLive
        }
        #expect(fixture.persistedChanges == 1)

        fixture.repo.isEnabled = false
        #expect(fixture.persistedChanges == 2)
        try await waitUntil("worker stops") {
            fixture.repo.worker.state == .stopped
        }
    }

    @Test func reassigningTheSameDesiredStateIsANoOp() throws {
        let fixture = try makeFixture()

        fixture.repo.isEnabled = false

        #expect(fixture.persistedChanges == 0)
        #expect(fixture.repo.worker.state == .stopped)
    }

    @Test func enablingWithALocateFailureLandsInFailedWithTheToggleOn() throws {
        let fixture = try makeFixture()
        fixture.executable = .failure(LocateFailure())

        fixture.repo.isEnabled = true

        #expect(fixture.repo.isEnabled)
        #expect(fixture.repo.worker.state == .failed(reason: "cursor-agent was not found"))
        #expect(fixture.persistedChanges == 1)
    }

    @Test func disablingAFailedRepoAcknowledgesTheFailure() throws {
        let fixture = try makeFixture()
        fixture.executable = .failure(LocateFailure())
        fixture.repo.isEnabled = true
        #expect(fixture.repo.worker.state == .failed(reason: "cursor-agent was not found"))

        fixture.repo.isEnabled = false

        // Switched off means not running *and* not failed — no red status
        // on a disabled row.
        #expect(fixture.repo.worker.state == .stopped)
    }

    // MARK: - Options

    @Test func optionsEditsNotifyPersistenceOnlyOnRealChange() throws {
        let fixture = try makeFixture()

        fixture.repo.options = .standard
        #expect(fixture.persistedChanges == 0)

        var renamed = WorkerOptions.standard
        renamed.displayName = "Renamed"
        fixture.repo.options = renamed
        #expect(fixture.persistedChanges == 1)
    }

    // MARK: - Launch restore

    @Test func startIfEnabledStartsOnlyWhenEnabled() async throws {
        let fixture = try makeFixture()

        fixture.repo.startIfEnabled()
        #expect(fixture.repo.worker.state == .stopped)

        fixture.repo.isEnabled = true
        try await waitUntil("worker reaches running") {
            fixture.repo.worker.state.isLive
        }
        let runningState = fixture.repo.worker.state

        // Already live: a second restore call must not respawn.
        fixture.repo.startIfEnabled()
        #expect(fixture.repo.worker.state == runningState)

        fixture.repo.isEnabled = false
        try await waitUntil("worker stops") {
            fixture.repo.worker.state == .stopped
        }
    }

    // MARK: - Retry

    @Test func retryFromFailedRespawnsWithoutTouchingDesiredState() async throws {
        let fixture = try makeFixture()
        let stub = try fixture.executable.get()
        fixture.executable = .failure(LocateFailure())
        fixture.repo.isEnabled = true
        #expect(fixture.repo.worker.state.isLive == false)
        let persistedBefore = fixture.persistedChanges

        fixture.executable = .success(stub)
        fixture.repo.retry()

        try await waitUntil("worker reaches running") {
            fixture.repo.worker.state.isLive
        }
        #expect(fixture.repo.isEnabled)
        // Retry is transient: nothing new to persist.
        #expect(fixture.persistedChanges == persistedBefore)

        fixture.repo.isEnabled = false
        try await waitUntil("worker stops") {
            fixture.repo.worker.state == .stopped
        }
    }

    @Test func retryOutsideAnEnabledFailedStateIsANoOp() async throws {
        let fixture = try makeFixture()

        // Stopped + disabled: nothing to retry.
        fixture.repo.retry()
        #expect(fixture.repo.worker.state == .stopped)

        // Running: retry must not respawn.
        fixture.repo.isEnabled = true
        try await waitUntil("worker reaches running") {
            fixture.repo.worker.state.isLive
        }
        let runningState = fixture.repo.worker.state
        fixture.repo.retry()
        #expect(fixture.repo.worker.state == runningState)

        fixture.repo.isEnabled = false
        try await waitUntil("worker stops") {
            fixture.repo.worker.state == .stopped
        }

        // Failed + disabled (only constructible programmatically now that
        // disabling acknowledges a failure): retry mirrors the Retry
        // button's isEnabled gate and must not start anything.
        fixture.repo.worker.recordStartFailure(reason: "boom")
        fixture.repo.retry()
        #expect(fixture.repo.worker.state == .failed(reason: "boom"))
    }

    // MARK: - Restart

    @Test func restartRespawnsWithTheCurrentOptions() async throws {
        let fixture = try makeFixture()
        fixture.repo.isEnabled = true
        try await waitUntil("worker reaches running") {
            fixture.repo.worker.state.isLive
        }
        let firstPid = try #require(pid(of: fixture.repo.worker.state))

        var renamed = WorkerOptions.standard
        renamed.displayName = "Renamed"
        fixture.repo.options = renamed
        fixture.repo.restart()
        #expect(fixture.repo.worker.state == .stopping(restartPending: true))

        try await waitUntil("replacement worker reaches running") {
            if case .running = fixture.repo.worker.state { true } else { false }
        }
        let secondPid = try #require(pid(of: fixture.repo.worker.state))
        #expect(secondPid != firstPid)

        // The respawn's argv (logged as the start header) carries the edit.
        let log = try String(contentsOf: fixture.repo.worker.logFileURL, encoding: .utf8)
        #expect(log.contains("--name Renamed"))

        fixture.repo.isEnabled = false
        try await waitUntil("worker stops") {
            fixture.repo.worker.state == .stopped
        }
    }

    @Test func restartWhileNotRunningIsANoOp() throws {
        let fixture = try makeFixture()

        fixture.repo.restart()
        #expect(fixture.repo.worker.state == .stopped)

        fixture.repo.isEnabled = true
        fixture.repo.isEnabled = false // Now .stopping — restart must not queue.
        fixture.repo.restart()
        #expect(fixture.repo.worker.state == .stopping(restartPending: false))
    }

    @Test func restartWithALocateFailureKeepsTheWorkerRunning() async throws {
        let fixture = try makeFixture()
        fixture.repo.isEnabled = true
        try await waitUntil("worker reaches running") {
            fixture.repo.worker.state.isLive
        }
        let runningState = fixture.repo.worker.state

        // The executable vanished since the last start: restarting would
        // trade a working process for a failure, so it must bail up front.
        fixture.executable = .failure(LocateFailure())
        fixture.repo.restart()

        #expect(fixture.repo.worker.state == runningState)

        fixture.repo.isEnabled = false
        try await waitUntil("worker stops") {
            fixture.repo.worker.state == .stopped
        }
    }
}
