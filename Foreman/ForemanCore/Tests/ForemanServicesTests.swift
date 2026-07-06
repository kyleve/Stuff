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
            repos: [:],
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
            configuration.repos[
                RepoID(rootURL: scanDirectory
                    .appendingPathComponent("Restored", isDirectory: true)),
            ] = RepoConfiguration(isEnabled: true, isFavorite: false, options: .standard)
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
        #expect(try fixture.store.load().repos[repo.id]?.isEnabled == true)

        repo.isEnabled = false
        // Back to a fully default record: the entry is dropped entirely.
        #expect(try fixture.store.load().repos[repo.id] == nil)
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
        #expect(try fixture.store.load().repos[repo.id]?.options == renamed)

        repo.options = .standard
        #expect(try fixture.store.load().repos[repo.id] == nil)
    }

    @Test func favoritingWritesThroughAndClearingDropsTheEntry() throws {
        let fixture = try makeFixture(repoNames: ["Thing"])
        fixture.services.start()
        let repo = try #require(fixture.services.repos.first)

        repo.isFavorite = true
        #expect(try fixture.store.load().repos[repo.id]?.isFavorite == true)

        // Favoriting alone doesn't enable the worker.
        #expect(try fixture.store.load().repos[repo.id]?.isEnabled == false)
        #expect(repo.worker.state == .stopped)

        // Unfavoriting a repo with no other customization drops the entry.
        repo.isFavorite = false
        #expect(try fixture.store.load().repos[repo.id] == nil)
    }

    @Test func disablingAFavoritedRepoKeepsItsEntry() async throws {
        let fixture = try makeFixture(repoNames: ["Thing"])
        fixture.services.start()
        let repo = try #require(fixture.services.repos.first)

        repo.isFavorite = true
        repo.isEnabled = true
        try await waitUntil("worker reaches running") {
            repo.worker.state.isLive
        }

        // Disabling clears the enabled flag but the favorite is separate state,
        // so the record survives (not dropped as a no-op).
        repo.isEnabled = false
        let saved = try #require(try fixture.store.load().repos[repo.id])
        #expect(!saved.isEnabled)
        #expect(saved.isFavorite)

        try await waitUntil("worker stops") {
            repo.worker.state == .stopped
        }
    }

    @Test func savedFavoriteIsRestoredOnLaunch() throws {
        let fixture = try makeFixture(repoNames: ["Pinned"]) { configuration, scanDirectory in
            configuration.repos[
                RepoID(rootURL: scanDirectory
                    .appendingPathComponent("Pinned", isDirectory: true)),
            ] = RepoConfiguration(isEnabled: false, isFavorite: true, options: .standard)
        }

        fixture.services.start()

        let pinned = try #require(fixture.services.repos.first)
        #expect(pinned.isFavorite)
        #expect(!pinned.isEnabled)
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
            configuration.repos[foreign] = RepoConfiguration(
                isEnabled: true,
                isFavorite: false,
                options: .standard,
            )
            configuration.repos[gone] = RepoConfiguration(
                isEnabled: true,
                isFavorite: false,
                options: WorkerOptions(
                    displayName: "Gone",
                    assignment: .shared,
                    labels: [],
                    idleReleaseTimeoutSeconds: 0,
                    verbose: false,
                ),
            )
        }

        fixture.services.start()

        let saved = try fixture.store.load()
        #expect(saved.repos[foreign]?.isEnabled == true)
        #expect(try saved.repos[#require(stale)] == nil)
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

    // MARK: - Control (MCP)

    @Test func adoptRecordsProvenanceEnablesAndPersists() async throws {
        let fixture = try makeControlServicesFixture(repoNames: ["Main"])
        fixture.services.start()
        try addGitDirectory("Copy", in: fixture.scanDirectory)
        let copy = fixture.scanDirectory.appendingPathComponent("Copy", isDirectory: true)
        let parentID = RepoID(rootURL: fixture.scanDirectory.appendingPathComponent("Main"))
        let provenance = CopyProvenance(kind: .worktree, parentRepoID: parentID, branch: "task")

        let status = try fixture.services.adoptAndStartWorker(at: copy, provenance: provenance)
        #expect(status.name == "Copy")
        #expect(status.enabled)
        #expect(status.provenance?.kind == "worktree")

        let repo = try #require(fixture.services.repos.first { $0.name == "Copy" })
        #expect(repo.provenance == provenance)
        #expect(repo.isEnabled)
        try await waitUntil("copy worker running") { repo.worker.state.isLive }

        let saved = try #require(try fixture.store.load().repos[RepoID(rootURL: copy)])
        #expect(saved.provenance == provenance)
        #expect(saved.isEnabled)

        fixture.services.stopAll()
        try await waitUntil("copy worker stops") { repo.worker.state == .stopped }
    }

    @Test func adoptRejectsAPathOutsideTheScanDirectory() throws {
        let fixture = try makeControlServicesFixture(repoNames: [])
        fixture.services.start()
        let outside = fixture.base.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(
            at: outside.appendingPathComponent(".git"),
            withIntermediateDirectories: true,
        )
        #expect(throws: ControlError.self) {
            try fixture.services.adoptAndStartWorker(
                at: outside,
                provenance: CopyProvenance(
                    kind: .clone,
                    parentRepoID: RepoID(rawValue: "/x"),
                    branch: "b",
                ),
            )
        }
    }

    @Test func adoptRejectsANonGitDirectory() throws {
        let fixture = try makeControlServicesFixture(repoNames: [])
        fixture.services.start()
        let notGit = fixture.scanDirectory.appendingPathComponent("NotGit", isDirectory: true)
        try FileManager.default.createDirectory(at: notGit, withIntermediateDirectories: true)
        #expect(throws: ControlError.self) {
            try fixture.services.adoptAndStartWorker(
                at: notGit,
                provenance: CopyProvenance(
                    kind: .clone,
                    parentRepoID: RepoID(rawValue: "/x"),
                    branch: "b",
                ),
            )
        }
    }

    @Test func describeIncludesProvenanceForAdoptedCopies() throws {
        let fixture = try makeControlServicesFixture(repoNames: ["Main"])
        fixture.services.start()
        try addGitDirectory("Copy", in: fixture.scanDirectory)
        let copy = fixture.scanDirectory.appendingPathComponent("Copy", isDirectory: true)
        let parentID = RepoID(rootURL: fixture.scanDirectory.appendingPathComponent("Main"))
        try fixture.services.adoptAndStartWorker(
            at: copy,
            provenance: CopyProvenance(kind: .clone, parentRepoID: parentID, branch: "b"),
        )

        let described = fixture.services.describe()
        #expect(described.scanDirectory == fixture.scanDirectory.path)
        let copyStatus = try #require(described.repos.first { $0.name == "Copy" })
        #expect(copyStatus.provenance?.kind == "clone")
        #expect(copyStatus.provenance?.parentRepoID == parentID.rawValue)
        let mainStatus = try #require(described.repos.first { $0.name == "Main" })
        #expect(mainStatus.provenance == nil)

        fixture.services.stopAll()
    }

    @Test func removeCopyStopsTheWorkerRemovesTheCopyAndPrunes() async throws {
        let fixture = try makeControlServicesFixture(repoNames: ["Main"])
        fixture.services.start()
        try addGitDirectory("Copy", in: fixture.scanDirectory)
        let copy = fixture.scanDirectory.appendingPathComponent("Copy", isDirectory: true)
        let parentID = RepoID(rootURL: fixture.scanDirectory.appendingPathComponent("Main"))
        try fixture.services.adoptAndStartWorker(
            at: copy,
            provenance: CopyProvenance(kind: .worktree, parentRepoID: parentID, branch: "task"),
        )
        let repo = try #require(fixture.services.repos.first { $0.name == "Copy" })
        try await waitUntil("copy worker running") { repo.worker.state.isLive }

        try await fixture.services.removeCopy(at: copy)

        #expect(fixture.remover.worktreeRemovals.count == 1)
        #expect(fixture.remover.worktreeRemovals.first?.path.lastPathComponent == "Copy")
        #expect(fixture.remover.worktreeRemovals.first?.parentRepoPath.lastPathComponent == "Main")
        #expect(!fixture.services.repos.contains { $0.name == "Copy" })
        #expect(try fixture.store.load().repos[RepoID(rootURL: copy)] == nil)
    }

    @Test func removeCopyOfACloneUsesTheCloneRemover() async throws {
        let fixture = try makeControlServicesFixture(repoNames: ["Main"])
        fixture.services.start()
        try addGitDirectory("Clone", in: fixture.scanDirectory)
        let clone = fixture.scanDirectory.appendingPathComponent("Clone", isDirectory: true)
        let parentID = RepoID(rootURL: fixture.scanDirectory.appendingPathComponent("Main"))
        try fixture.services.adoptAndStartWorker(
            at: clone,
            provenance: CopyProvenance(kind: .clone, parentRepoID: parentID, branch: "b"),
        )
        let repo = try #require(fixture.services.repos.first { $0.name == "Clone" })
        try await waitUntil("clone worker running") { repo.worker.state.isLive }

        try await fixture.services.removeCopy(at: clone)

        #expect(fixture.remover.cloneRemovals.map(\.lastPathComponent) == ["Clone"])
        #expect(fixture.remover.worktreeRemovals.isEmpty)
        #expect(!fixture.services.repos.contains { $0.name == "Clone" })
    }

    @Test func removeCopyRejectsARepoWithoutProvenance() async throws {
        let fixture = try makeControlServicesFixture(repoNames: ["Plain"])
        fixture.services.start()
        let plain = fixture.scanDirectory.appendingPathComponent("Plain", isDirectory: true)

        await #expect(throws: ControlError.self) {
            try await fixture.services.removeCopy(at: plain)
        }
        #expect(fixture.remover.worktreeRemovals.isEmpty)
        #expect(fixture.remover.cloneRemovals.isEmpty)
        #expect(fixture.services.repos.contains { $0.name == "Plain" })
    }

    @Test func removeCopySurfacesRemoverFailureAndKeepsTheRepo() async throws {
        let fixture = try makeControlServicesFixture(repoNames: ["Main"])
        fixture.services.start()
        try addGitDirectory("Copy", in: fixture.scanDirectory)
        let copy = fixture.scanDirectory.appendingPathComponent("Copy", isDirectory: true)
        let parentID = RepoID(rootURL: fixture.scanDirectory.appendingPathComponent("Main"))
        try fixture.services.adoptAndStartWorker(
            at: copy,
            provenance: CopyProvenance(kind: .worktree, parentRepoID: parentID, branch: "task"),
        )
        let repo = try #require(fixture.services.repos.first { $0.name == "Copy" })
        try await waitUntil("copy worker running") { repo.worker.state.isLive }
        fixture.remover.failure = CopyRemovalTestError()

        await #expect(throws: ControlError.self) {
            try await fixture.services.removeCopy(at: copy)
        }
        // The removal failed, so the copy is restored to how we found it: the
        // repo survives, stays enabled, and its worker is running again rather
        // than being silently left stopped/disabled.
        #expect(fixture.services.repos.contains { $0.name == "Copy" })
        #expect(repo.isEnabled)
        try await waitUntil("worker running again after failed removal") {
            repo.worker.state.isLive
        }
    }
}
