import Foundation
import Observation

/// The root of the Foreman model tree. Owns every other model object —
/// ``AppSettings``, the ``RepoDiscovery`` holding the ``Repo``s, the config
/// store, and the ``SleepInhibitor`` — and funnels their changes:
///
/// - persisted mutations (`Repo.isEnabled`/`options`, `AppSettings`) write
///   through into the retained ``ForemanConfiguration`` and save;
/// - every ``Worker`` state transition recomputes the sleep assertion over
///   the whole tree.
///
/// `configuration` stays the *retained backing store* rather than being
/// rebuilt from the tree on save: entries for repos under other scan
/// directories aren't represented in the tree but must survive (they
/// re-apply when the user switches back).
@MainActor
@Observable
public final class ForemanServices {
    /// The most recent user-visible problem at the tree level: unreadable
    /// config, failed scan, failed save. Per-repo failures live on the
    /// repo's worker instead. Cleared by the next successful scan.
    public private(set) var issueMessage: String?

    /// Global settings; created from the loaded configuration.
    ///
    /// `unowned` is safe here (and on `discovery`): both objects are reached
    /// only through a live `ForemanServices`, and their callbacks fire from
    /// direct property writes, not deferred work. Contrast `makeRepo`, whose
    /// products escape to views and outlive-by-retention is possible.
    @ObservationIgnored
    public private(set) lazy var settings: AppSettings = .init(
        scanDirectory: configuration.scanDirectory,
        agentExecutable: configuration.agentExecutable,
        onPersistentChange: { [unowned self] in settingsDidChange($0) },
    )

    /// The discovered repositories (and their workers).
    @ObservationIgnored
    public private(set) lazy var discovery: RepoDiscovery = RepoDiscovery { [unowned self] in
        makeRepo($0)
    }

    /// Convenience mirror of `discovery.repos` for the UI.
    public var repos: [Repo] {
        discovery.repos
    }

    /// The discovered repos grouped for the sidebar: enabled on top, disabled
    /// below, favorites floated to the top of each section. See ``RepoSection``.
    public var repoSections: [RepoSection] {
        RepoSection.sections(from: discovery.repos)
    }

    public var isAnyWorkerLive: Bool {
        discovery.isAnyWorkerLive
    }

    /// Whether the idle-sleep assertion is currently held.
    public var isInhibitingSleep: Bool {
        sleepInhibitor.isActive
    }

    /// Whether Foreman is registered to launch at login. Backed by
    /// `SMAppService` (the OS owns the real state), so this is a live read of
    /// the login-item status. The setter registers/unregisters and, on
    /// failure, logs *and* surfaces ``loginItemError`` while leaving the
    /// observed value honest — a failed toggle stays off rather than falsely
    /// on. A successful toggle clears the error.
    public var startsAtLogin: Bool {
        get { loginItem.isEnabled }
        set {
            do {
                try loginItem.setEnabled(newValue)
                loginItemError = nil
            } catch {
                Self.logger.error("Couldn't update the login item: \(error)")
                loginItemError = newValue
                    ? String(localized: .loginItemTurnOnFailed(error: error.localizedDescription))
                    : String(localized: .loginItemTurnOffFailed(error: error.localizedDescription))
            }
        }
    }

    /// The login item is registered but macOS is waiting for the user to
    /// approve it in System Settings before it will launch.
    public var loginItemNeedsApproval: Bool {
        loginItem.needsApproval
    }

    /// The most recent login-item failure, surfaced in the settings window's
    /// General pane (not the main-window banner — the toggle lives here).
    /// Cleared by the next successful toggle.
    public private(set) var loginItemError: String?

    /// Re-reads the login-item status from the OS; it can change outside the
    /// app (System Settings › General › Login Items), so the UI refreshes it
    /// when the settings window reappears.
    public func refreshLoginItemStatus() {
        loginItem.refresh()
    }

    /// Opens System Settings › General › Login Items so the user can approve a
    /// pending login item.
    public func openSystemSettingsLoginItems() {
        loginItem.openSystemSettingsLoginItems()
    }

    /// Where worker logs land: `~/Library/Logs/Foreman`.
    public static var defaultLogDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Foreman", isDirectory: true)
    }

    /// The Unix domain socket the app listens on for MCP control requests:
    /// `~/Library/Application Support/com.stuff.foreman/control.sock`. The
    /// `foreman-mcp` server connects here (its `FOREMAN_CONTROL_SOCKET`
    /// default is the same path).
    public static var controlSocketURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/com.stuff.foreman/control.sock",
                isDirectory: false,
            )
    }

    private static let logger = ForemanLog.channel(.services)

    @ObservationIgnored private var configuration: ForemanConfiguration
    /// Set when the config file existed but couldn't be read; surfaced by
    /// ``start()`` after the initial scan (which clears `issueMessage`).
    @ObservationIgnored private let configLoadFailure: String?
    private let configStore: WorkerConfigStore
    private let logDirectory: URL
    private let sleepInhibitor: SleepInhibitor
    private let loginItem: LoginItemController
    private let locator = CursorAgentLocator()
    private let copyRemover: any RepoCopyRemoving

    public convenience init(configStore: WorkerConfigStore, logDirectory: URL) {
        self.init(
            configStore: configStore,
            logDirectory: logDirectory,
            sleepInhibitor: SleepInhibitor(),
            loginItem: LoginItemController(),
        )
    }

    /// Loads the configuration eagerly so `settings` and the repo factory
    /// never see pre-load defaults. A file that exists but can't be read
    /// keeps the in-memory defaults without overwriting the corrupt file —
    /// nothing is saved until the user changes something deliberately.
    @_spi(Testing)
    public init(
        configStore: WorkerConfigStore,
        logDirectory: URL,
        sleepInhibitor: SleepInhibitor,
        loginItem: LoginItemController,
        copyRemover: any RepoCopyRemoving = SystemRepoCopyRemover(),
    ) {
        self.configStore = configStore
        self.logDirectory = logDirectory
        self.sleepInhibitor = sleepInhibitor
        self.loginItem = loginItem
        self.copyRemover = copyRemover
        do {
            configuration = try configStore.load()
            configLoadFailure = nil
        } catch {
            Self.logger.error("Couldn't load configuration: \(error)")
            configuration = .initial
            configLoadFailure = String(localized: .configLoadFailure)
        }
    }

    // MARK: - Lifecycle

    /// First scan and launch restore: starts the workers that were enabled
    /// last time. Called once at app launch.
    public func start() {
        rescan()
        for repo in discovery.repos {
            repo.startIfEnabled()
        }
        // Set after rescan (which clears `issueMessage` on success) — a
        // corrupt config should stay visible.
        if let configLoadFailure {
            issueMessage = configLoadFailure
        }
    }

    /// Stops every worker; the app's quit path.
    public func stopAll() {
        discovery.stopAllWorkers()
    }

    /// Re-scans the current scan directory. Vanished repos' workers are
    /// stopped (inside `RepoDiscovery`), and saved entries for repos deleted
    /// from the current scan directory are pruned. A failed scan keeps the
    /// last good repos and reports the problem.
    public func rescan() {
        let directory = settings.resolvedScanDirectory
        do {
            try discovery.rescan(in: directory)
            issueMessage = nil
            // Draining ids count as discovered: pruning a repo mid-drain
            // would strand it toggle-on-but-unsaved if it's resurrected.
            // If it stays gone, the prune lands once the drain completes.
            if configuration.prune(
                discovered: discovery.retainedRepoIDs,
                under: directory,
            ) {
                persist()
            }
        } catch {
            Self.logger.error("Repo scan failed: \(error)")
            issueMessage = String(localized: .scanFailed(
                path: directory.path,
                error: error.localizedDescription,
            ))
        }
    }

    // MARK: - Control (MCP)

    /// A snapshot of the scan directory and every known repo, for the MCP's
    /// `list_repos` and for placing new copies. Pure read of the live tree.
    public func describe() -> DescribeResultDTO {
        DescribeResultDTO(
            scanDirectory: settings.resolvedScanDirectory.path,
            repos: discovery.repos.map { RepoStatusDTO(repo: $0) },
        )
    }

    /// Records that the repo at `path` is a Foreman-created copy and starts its
    /// worker, returning the resulting status.
    ///
    /// `path` must be an immediate subdirectory of the scan directory (that's
    /// all `RepoDiscovery` sees) and a git working copy; otherwise this throws
    /// a ``ControlError`` describing the problem rather than silently doing
    /// nothing. Safe to call again for an already-adopted copy — it refreshes
    /// the provenance and makes sure the worker is running.
    @discardableResult
    public func adoptAndStartWorker(
        at path: URL,
        provenance: CopyProvenance,
    ) throws -> RepoStatusDTO {
        let copy = path.standardizedFileURL
        let scanDirectory = settings.resolvedScanDirectory.standardizedFileURL

        guard copy.deletingLastPathComponent().path == scanDirectory.path else {
            throw ControlError.pathNotUnderScanDirectory(
                path: copy.path,
                scanDirectory: scanDirectory.path,
            )
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: copy.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              FileManager.default.fileExists(atPath: copy.appendingPathComponent(".git").path)
        else {
            throw ControlError.notAGitRepository(path: copy.path)
        }

        // Discover the freshly-created copy, then record its provenance on the
        // live repo (which writes through) — this also covers the case where a
        // prior rescan had already picked the directory up without provenance.
        rescan()
        let id = RepoID(rootURL: copy)
        guard let repo = discovery.repos.first(where: { $0.id == id }) else {
            throw ControlError.repoNotFound(path: copy.path)
        }
        repo.provenance = provenance

        // Enabling starts the worker; if it was already enabled (a re-adopt),
        // startIfEnabled() (re)starts it when it isn't already live — .failed
        // included, since that isn't a live state.
        if repo.isEnabled {
            repo.startIfEnabled()
        } else {
            repo.isEnabled = true
        }
        Self.logger.info("Adopted \(provenance.kind.rawValue) copy at \(copy.path)")
        return RepoStatusDTO(repo: repo)
    }

    /// Stops the worker for the copy at `path` and removes it: a worktree via
    /// `git worktree remove`, a clone by moving it to the Trash. Throws a
    /// ``ControlError`` if the path isn't a recorded copy or the removal
    /// fails, so a failure is never mistaken for success.
    public func removeCopy(at path: URL) async throws {
        let copy = path.standardizedFileURL
        let id = RepoID(rootURL: copy)
        let repo = discovery.repos.first { $0.id == id }
        guard let provenance = repo?.provenance ?? configuration.configuration(for: id).provenance
        else {
            throw ControlError.notACopy(path: copy.path)
        }

        // A live cursor-agent holds the worktree open, so stop it and wait for
        // the process to actually exit before touching the files.
        if let repo, repo.worker.state.isLive {
            repo.isEnabled = false
            try await waitForWorkerToStop(repo, path: copy)
        }

        do {
            switch provenance.kind {
                case .worktree:
                    try copyRemover.removeWorktree(
                        at: copy,
                        parentRepoPath: URL(fileURLWithPath: provenance.parentRepoID.rawValue),
                    )
                case .clone:
                    try copyRemover.removeClone(at: copy)
            }
        } catch {
            Self.logger.error("Couldn't remove copy at \(copy.path): \(error)")
            throw ControlError.removeFailed(reason: error.localizedDescription)
        }

        Self.logger.info("Removed \(provenance.kind.rawValue) copy at \(copy.path)")
        rescan()
    }

    /// Polls until `repo`'s worker settles at a non-live state, throwing
    /// ``ControlError/workerDidNotStop(path:)`` if it hasn't within `timeout`.
    private func waitForWorkerToStop(
        _ repo: Repo,
        path: URL,
        timeout: Duration = .seconds(10),
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while repo.worker.state.isLive {
            if clock.now >= deadline {
                throw ControlError.workerDidNotStop(path: path.path)
            }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    // MARK: - Tree wiring

    /// Thrown by a repo's executable resolution when the owning services
    /// have been released — reachable only if something (a view, a test)
    /// retains a `Repo` beyond the root's life and starts it.
    private struct ServicesReleasedError: Error, LocalizedError {
        var errorDescription: String? {
            String(localized: .servicesShuttingDown)
        }
    }

    /// `Repo`/`Worker` escape the tree (SwiftUI views hold them via
    /// `@Bindable`), so their callbacks capture `self` weakly: a retained
    /// repo whose worker exits after the root is gone must degrade to a
    /// no-op, not crash on a dangling reference.
    private func makeRepo(_ scanned: ScannedRepo) -> Repo {
        let record = configuration.configuration(for: scanned.id)
        return Repo(
            scanned: scanned,
            isEnabled: record.isEnabled,
            isFavorite: record.isFavorite,
            options: record.options,
            provenance: record.provenance,
            worker: Worker(
                name: scanned.name,
                workerDirectory: scanned.rootURL,
                logDirectory: logDirectory,
                onStateChange: { [weak self] in self?.workerStateDidChange() },
            ),
            resolveExecutable: { [weak self] in
                guard let self else { throw ServicesReleasedError() }
                return try locator.locate(explicit: settings.agentExecutable)
            },
            onPersistentChange: { [weak self] in self?.repoDidChange($0) },
        )
    }

    private func repoDidChange(_ repo: Repo) {
        // The repo is the source of truth for its whole persisted record.
        let record = RepoConfiguration(
            isEnabled: repo.isEnabled,
            isFavorite: repo.isFavorite,
            options: repo.options,
            provenance: repo.provenance,
        )
        if record == .standard {
            // A fully default record reads identically to an absent entry;
            // dropping it keeps the file from accumulating no-op records.
            configuration.repos.removeValue(forKey: repo.id)
        } else {
            configuration.repos[repo.id] = record
        }
        persist()
    }

    private func settingsDidChange(_ change: AppSettings.Change) {
        configuration.scanDirectory = settings.scanDirectory
        configuration.agentExecutable = settings.agentExecutable
        persist()
        if case .scanDirectory = change {
            rescan()
        }
    }

    private func workerStateDidChange() {
        sleepInhibitor.setActive(
            discovery.isAnyWorkerLive,
            reason: "Cursor agent workers are running",
        )
    }

    private func persist() {
        do {
            try configStore.save(configuration)
        } catch {
            Self.logger.error("Couldn't save configuration: \(error)")
            issueMessage = String(localized: .saveFailed(error: error.localizedDescription))
        }
    }
}
