@_spi(Testing) import ForemanCore
import Foundation
import Testing

@MainActor
struct ForemanServicesTests {
    private struct Fixture {
        let services: ForemanServices
        let store: WorkerConfigStore
        let base: URL
        let scanDirectory: URL
        let executable: URL
        let sleep: SleepAssertionRecorder
        let login: LoginItemRecorder
    }

    /// A config-store + scan-directory sandbox. `repoNames` become git repos
    /// in the scan directory; `configure` edits the saved configuration
    /// (which already points `agentExecutable` at a long-running stub) and
    /// receives the scan directory for building `RepoID`s. `loginBackend`
    /// injects a login-item double (defaults to a fresh one that succeeds).
    private func makeFixture(
        repoNames: [String],
        loginBackend: LoginItemRecorder? = nil,
        configure: (inout ForemanConfiguration, _ scanDirectory: URL) -> Void = { _, _ in },
    ) throws -> Fixture {
        let base = try makeTemporaryDirectory()
        let scanDirectory = base.appendingPathComponent("Development", isDirectory: true)
        try FileManager.default.createDirectory(
            at: scanDirectory,
            withIntermediateDirectories: true,
        )
        for name in repoNames {
            try addRepo(name, in: scanDirectory)
        }
        let executable = try makeStubExecutable(
            in: base,
            script: "#!/bin/sh\nwhile true; do sleep 0.1; done\n",
        )

        let store = WorkerConfigStore(directory: base.appendingPathComponent("config"))
        var configuration = ForemanConfiguration(
            scanDirectory: scanDirectory,
            agentExecutable: executable,
            enabledRepoIDs: [],
            repoOptions: [:],
        )
        configure(&configuration, scanDirectory)
        try store.save(configuration)

        let recorder = SleepAssertionRecorder()
        let login = loginBackend ?? LoginItemRecorder()
        let services = ForemanServices(
            configStore: store,
            logDirectory: base.appendingPathComponent("logs"),
            sleepInhibitor: SleepInhibitor(backend: recorder),
            loginItem: LoginItemController(backend: login),
        )
        return Fixture(
            services: services,
            store: store,
            base: base,
            scanDirectory: scanDirectory,
            executable: executable,
            sleep: recorder,
            login: login,
        )
    }

    private func addRepo(_ name: String, in scanDirectory: URL) throws {
        try FileManager.default.createDirectory(
            at: scanDirectory.appendingPathComponent("\(name)/.git"),
            withIntermediateDirectories: true,
        )
    }

    // MARK: - Launch

    @Test func startScansAndRestoresEnabledWorkers() async throws {
        let fixture = try makeFixture(repoNames: [
            "Idle",
            "Restored",
        ]) { configuration, scanDirectory in
            configuration.enabledRepoIDs = [
                RepoID(rootURL: scanDirectory
                    .appendingPathComponent("Restored", isDirectory: true)),
            ]
        }

        fixture.services.start()

        #expect(fixture.services.repos.map(\.name) == ["Idle", "Restored"])
        #expect(fixture.services.issueMessage == nil)
        let restored = try #require(fixture.services.repos.first { $0.name == "Restored" })
        let idle = try #require(fixture.services.repos.first { $0.name == "Idle" })
        #expect(restored.isEnabled)
        #expect(!idle.isEnabled)
        try await waitUntil("restored worker reaches running") {
            restored.worker.state.isLive
        }
        #expect(idle.worker.state == .stopped)

        fixture.services.stopAll()
        try await waitUntil("worker stops") {
            restored.worker.state == .stopped
        }
    }

    @Test func corruptConfigSurfacesTheIssueAndKeepsDefaultsUnsaved() throws {
        let base = try makeTemporaryDirectory()
        let configDirectory = base.appendingPathComponent("config")
        try FileManager.default.createDirectory(
            at: configDirectory,
            withIntermediateDirectories: true,
        )
        let configFile = configDirectory.appendingPathComponent("configuration.json")
        try Data("not json".utf8).write(to: configFile)

        let services = ForemanServices(
            configStore: WorkerConfigStore(directory: configDirectory),
            logDirectory: base.appendingPathComponent("logs"),
            sleepInhibitor: SleepInhibitor(backend: SleepAssertionRecorder()),
            loginItem: LoginItemController(backend: LoginItemRecorder()),
        )
        services.start()

        // The issue survives the initial scan, and the corrupt file wasn't
        // overwritten by some incidental save.
        #expect(services.issueMessage == "Couldn't read saved settings — using defaults.")
        #expect(try String(contentsOf: configFile, encoding: .utf8) == "not json")
    }

    // MARK: - Persistence funnel

    @Test func toggleWritesThroughToTheSavedConfiguration() async throws {
        let fixture = try makeFixture(repoNames: ["Thing"])
        fixture.services.start()
        let repo = try #require(fixture.services.repos.first)

        repo.isEnabled = true
        try await waitUntil("worker reaches running") {
            repo.worker.state.isLive
        }
        #expect(try fixture.store.load().enabledRepoIDs == [repo.id])

        repo.isEnabled = false
        #expect(try fixture.store.load().enabledRepoIDs == [])
        try await waitUntil("worker stops") {
            repo.worker.state == .stopped
        }
    }

    @Test func optionsEditsPersistAndStandardOptionsDropTheEntry() throws {
        let fixture = try makeFixture(repoNames: ["Thing"])
        fixture.services.start()
        let repo = try #require(fixture.services.repos.first)

        var renamed = WorkerOptions.standard
        renamed.displayName = "Renamed"
        repo.options = renamed
        #expect(try fixture.store.load().repoOptions[repo.id] == renamed)

        repo.options = .standard
        #expect(try fixture.store.load().repoOptions[repo.id] == nil)
    }

    @Test func settingsChangesPersistAndAScanDirectoryChangeRescans() throws {
        let fixture = try makeFixture(repoNames: ["Old"])
        fixture.services.start()
        #expect(fixture.services.repos.map(\.name) == ["Old"])

        let elsewhere = fixture.base.appendingPathComponent("Elsewhere", isDirectory: true)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try addRepo("New", in: elsewhere)

        fixture.services.settings.scanDirectory = elsewhere

        #expect(fixture.services.repos.map(\.name) == ["New"])
        #expect(try fixture.store.load().scanDirectory == elsewhere)

        // An executable change persists but must not trigger a rescan (the
        // repo list is directory-driven).
        let otherAgent = fixture.base.appendingPathComponent("other-agent")
        fixture.services.settings.agentExecutable = otherAgent
        #expect(try fixture.store.load().agentExecutable == otherAgent)
        #expect(fixture.services.repos.map(\.name) == ["New"])
    }

    // MARK: - Launch at login

    @Test func startsAtLoginWritesThroughToTheLoginItem() throws {
        let fixture = try makeFixture(repoNames: [])
        #expect(!fixture.services.startsAtLogin)

        fixture.services.startsAtLogin = true
        #expect(fixture.services.startsAtLogin)
        #expect(fixture.login.registerCount == 1)

        fixture.services.startsAtLogin = false
        #expect(!fixture.services.startsAtLogin)
        #expect(fixture.login.unregisterCount == 1)
    }

    @Test func aFailedLoginItemToggleSurfacesTheErrorAndStaysHonest() throws {
        let fixture = try makeFixture(
            repoNames: [],
            loginBackend: LoginItemRecorder(failure: LoginItemTestError()),
        )
        fixture.services.start()
        #expect(fixture.services.loginItemError == nil)

        fixture.services.startsAtLogin = true

        // The registration failed, so the toggle stays off and the failure is
        // observable on the login-item channel (not the tree-level banner)
        // rather than silently swallowed.
        #expect(!fixture.services.startsAtLogin)
        #expect(fixture.services.loginItemError != nil)
        #expect(fixture.services.issueMessage == nil)
    }

    @Test func aSuccessfulToggleClearsAPriorLoginItemError() throws {
        let recorder = LoginItemRecorder(failure: LoginItemTestError())
        let fixture = try makeFixture(repoNames: [], loginBackend: recorder)

        fixture.services.startsAtLogin = true
        #expect(fixture.services.loginItemError != nil)

        // Recover: the next toggle succeeds and the stale error clears.
        recorder.failure = nil
        fixture.services.startsAtLogin = true
        #expect(fixture.services.startsAtLogin)
        #expect(fixture.services.loginItemError == nil)
    }

    @Test func pendingApprovalReadsAsEnabledAndNeedsApproval() throws {
        let fixture = try makeFixture(
            repoNames: [],
            loginBackend: LoginItemRecorder(status: .requiresApproval),
        )

        #expect(fixture.services.startsAtLogin)
        #expect(fixture.services.loginItemNeedsApproval)
    }

    // MARK: - Rescan

    @Test func rescanPrunesStaleEntriesButKeepsForeignScanDirectoryOnes() throws {
        let foreign = RepoID(rawValue: "/Users/dev/Elsewhere/Kept")
        var stale: RepoID?
        let fixture = try makeFixture(repoNames: ["Thing"]) { configuration, scanDirectory in
            let gone = RepoID(rootURL: scanDirectory
                .appendingPathComponent("Gone", isDirectory: true))
            stale = gone
            configuration.enabledRepoIDs = [foreign, gone]
            configuration.repoOptions[gone] = WorkerOptions(
                displayName: "Gone",
                assignment: .shared,
                labels: [],
                idleReleaseTimeoutSeconds: 0,
                verbose: false,
            )
        }

        fixture.services.start()

        let saved = try fixture.store.load()
        #expect(saved.enabledRepoIDs == [foreign])
        #expect(try saved.repoOptions[#require(stale)] == nil)
    }

    @Test func failedRescanKeepsReposAndReportsTheIssue() throws {
        let fixture = try makeFixture(repoNames: ["Thing"])
        fixture.services.start()
        #expect(fixture.services.issueMessage == nil)

        // Deleting the scan directory makes the next rescan fail; the last
        // good repo list must survive.
        try FileManager.default.removeItem(at: fixture.scanDirectory)
        fixture.services.rescan()

        #expect(fixture.services.repos.map(\.name) == ["Thing"])
        #expect(fixture.services.issueMessage?.contains("Couldn't scan") == true)
    }

    // MARK: - Sleep inhibition

    @Test func sleepAssertionCoversAllLiveWorkersInTheTree() async throws {
        let fixture = try makeFixture(repoNames: ["First", "Second"])
        fixture.services.start()
        let first = try #require(fixture.services.repos.first { $0.name == "First" })
        let second = try #require(fixture.services.repos.first { $0.name == "Second" })

        first.isEnabled = true
        second.isEnabled = true
        try await waitUntil("both workers reach running") {
            first.worker.state.isLive && second.worker.state.isLive
        }

        // One assertion covers all live workers; the second start doesn't
        // re-take it.
        #expect(fixture.sleep.begins == 1)
        #expect(fixture.services.isInhibitingSleep)

        fixture.services.stopAll()
        try await waitUntil("both workers stop") {
            first.worker.state == .stopped && second.worker.state == .stopped
        }
        #expect(fixture.sleep.ends == 1)
        #expect(!fixture.services.isInhibitingSleep)
    }

    @Test func sleepAssertionIsHeldWhileAVanishedRepoWorkerDrains() async throws {
        let fixture = try makeFixture(repoNames: ["Doomed"])
        fixture.services.start()
        let doomed = try #require(fixture.services.repos.first)

        doomed.isEnabled = true
        try await waitUntil("worker reaches running") {
            doomed.worker.state.isLive
        }
        #expect(fixture.sleep.begins == 1)

        try FileManager.default.removeItem(at: doomed.rootURL)
        fixture.services.rescan()

        // The repo left the tree but its process is still exiting — the
        // assertion must be released only when the exit lands.
        #expect(fixture.services.repos.isEmpty)
        try await waitUntil("drained worker stops") {
            doomed.worker.state == .stopped
        }
        #expect(fixture.sleep.ends == 1)
        #expect(!fixture.services.isInhibitingSleep)
    }
}
