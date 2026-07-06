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
                    ? "Couldn't turn on “Launch at login”: \(error.localizedDescription)"
                    : "Couldn't turn off “Launch at login”: \(error.localizedDescription)"
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
    ) {
        self.configStore = configStore
        self.logDirectory = logDirectory
        self.sleepInhibitor = sleepInhibitor
        self.loginItem = loginItem
        do {
            configuration = try configStore.load()
            configLoadFailure = nil
        } catch {
            Self.logger.error("Couldn't load configuration: \(error)")
            configuration = .initial
            configLoadFailure = "Couldn't read saved settings — using defaults."
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
            issueMessage =
                "Couldn't scan \(directory.path): \(error.localizedDescription)"
        }
    }

    // MARK: - Tree wiring

    /// Thrown by a repo's executable resolution when the owning services
    /// have been released — reachable only if something (a view, a test)
    /// retains a `Repo` beyond the root's life and starts it.
    private struct ServicesReleasedError: Error, LocalizedError {
        var errorDescription: String? {
            "Foreman is shutting down."
        }
    }

    /// `Repo`/`Worker` escape the tree (SwiftUI views hold them via
    /// `@Bindable`), so their callbacks capture `self` weakly: a retained
    /// repo whose worker exits after the root is gone must degrade to a
    /// no-op, not crash on a dangling reference.
    private func makeRepo(_ scanned: ScannedRepo) -> Repo {
        Repo(
            scanned: scanned,
            isEnabled: configuration.enabledRepoIDs.contains(scanned.id),
            options: configuration.options(for: scanned.id),
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
        if repo.isEnabled {
            configuration.enabledRepoIDs.insert(repo.id)
        } else {
            configuration.enabledRepoIDs.remove(repo.id)
        }
        if repo.options == .standard {
            // Standard options read identically to an absent entry; dropping
            // the entry keeps the file from accumulating no-op records.
            configuration.repoOptions.removeValue(forKey: repo.id)
        } else {
            configuration.repoOptions[repo.id] = repo.options
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
            issueMessage = "Couldn't save settings: \(error.localizedDescription)"
        }
    }
}
