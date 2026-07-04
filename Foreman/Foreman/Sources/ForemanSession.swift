import ForemanCore
import Foundation
import Observation

/// One repo row the menu renders. An `@Observable` class so the row's
/// `Toggle` binds to `$row.isEnabled` instead of a closure-built `Binding`;
/// flips funnel into the session's toggle intent.
@MainActor
@Observable
final class WorkerRow: Identifiable {
    let repo: Repo

    var isEnabled: Bool {
        didSet {
            guard oldValue != isEnabled else { return }
            onChange(self)
        }
    }

    private let onChange: @MainActor (WorkerRow) -> Void

    nonisolated var id: RepoID {
        repo.id
    }

    init(repo: Repo, isEnabled: Bool, onChange: @escaping @MainActor (WorkerRow) -> Void) {
        self.repo = repo
        self.isEnabled = isEnabled
        self.onChange = onChange
    }
}

/// The app-level view model: mirrors ForemanCore state for SwiftUI and exposes
/// the menu's intents (toggle a worker, edit options, rescan, change
/// settings). Core behavior — discovery, persistence, process supervision —
/// stays in ForemanCore; this class only orchestrates it.
@MainActor
@Observable
final class ForemanSession {
    /// Rows for the discovered repos, sorted by name.
    private(set) var rows: [WorkerRow] = []
    /// The most recent user-visible problem (config unreadable, scan failed,
    /// cursor-agent missing, …). Cleared by the next successful action.
    private(set) var issueMessage: String?
    private(set) var configuration: ForemanConfiguration = .initial

    var isInhibitingSleep: Bool {
        supervisor.isInhibitingSleep
    }

    var isAnyWorkerLive: Bool {
        rows.contains { supervisor.state(for: $0.repo.id).isLive }
    }

    private static let logger = ForemanLog.channel(.session)

    private let configStore: WorkerConfigStore
    private let supervisor: WorkerSupervisor
    private let discovery = RepoDiscovery()
    private let locator = CursorAgentLocator()

    init(configStore: WorkerConfigStore, supervisor: WorkerSupervisor) {
        self.configStore = configStore
        self.supervisor = supervisor
    }

    convenience init() {
        self.init(
            configStore: .applicationSupport(),
            supervisor: WorkerSupervisor(logDirectory: WorkerSupervisor.defaultLogDirectory),
        )
    }

    // MARK: - Lifecycle

    /// Loads the configuration, scans for repos, and restarts the workers
    /// that were enabled last time. Called once at app launch.
    func start() {
        var configLoadMessage: String?
        do {
            configuration = try configStore.load()
        } catch {
            // Keep the in-memory defaults but don't overwrite the corrupt
            // file until the user changes something deliberately.
            Self.logger.error("Couldn't load configuration: \(error)")
            configLoadMessage = "Couldn't read saved settings — using defaults."
        }
        rescan()
        for row in rows where configuration.enabledRepoIDs.contains(row.repo.id) {
            startWorker(for: row.repo)
        }
        // Set after rescan/start, which clear `issueMessage` on success —
        // a corrupt config should stay visible.
        if let configLoadMessage {
            issueMessage = configLoadMessage
        }
    }

    /// Stops every worker; the app's quit path.
    func stopAllWorkers() {
        supervisor.stopAll()
    }

    // MARK: - Repos

    /// Re-lists the scan directory, preserving toggle state for repos that
    /// remain. A failed scan keeps the last good rows and reports the problem.
    func rescan() {
        do {
            let repos = try discovery.repos(in: configuration.resolvedScanDirectory)
            rows = repos.map { repo in
                WorkerRow(
                    repo: repo,
                    isEnabled: configuration.enabledRepoIDs.contains(repo.id),
                ) { [weak self] row in
                    self?.applyToggle(row)
                }
            }
            issueMessage = nil
        } catch {
            Self.logger.error("Repo scan failed: \(error)")
            issueMessage =
                "Couldn't scan \(configuration.resolvedScanDirectory.path): \(error.localizedDescription)"
        }
    }

    func workerState(for repo: Repo) -> WorkerSupervisor.WorkerState {
        supervisor.state(for: repo.id)
    }

    func logFileURL(for repo: Repo) -> URL {
        supervisor.logFileURL(for: repo)
    }

    // MARK: - Worker control

    private func applyToggle(_ row: WorkerRow) {
        // A revert (set back to what the config already says) is a no-op, so
        // the didSet triggered by `row.isEnabled = oldValue` below can't loop.
        guard row.isEnabled != configuration.enabledRepoIDs.contains(row.repo.id) else { return }

        if row.isEnabled {
            guard startWorker(for: row.repo) else {
                row.isEnabled = false
                return
            }
            configuration.enabledRepoIDs.insert(row.repo.id)
        } else {
            supervisor.stop(row.repo.id)
            configuration.enabledRepoIDs.remove(row.repo.id)
        }
        persist()
    }

    /// Starts the worker for `repo`; returns whether a process was spawned
    /// (locating `cursor-agent` can fail before any spawn is attempted).
    @discardableResult
    private func startWorker(for repo: Repo) -> Bool {
        let executable: URL
        do {
            executable = try locator.locate(explicit: configuration.agentExecutable)
        } catch {
            Self.logger.error("Can't start worker for \(repo.name): \(error)")
            issueMessage = error.localizedDescription
            return false
        }
        supervisor.start(
            repo: repo,
            options: configuration.options(for: repo.id),
            executable: executable,
        )
        issueMessage = nil
        return true
    }

    // MARK: - Options & settings

    /// Saves `options` for `repo`. Options apply on the worker's next start,
    /// so the editor is only offered while the worker is stopped.
    func updateOptions(_ options: WorkerOptions, for repo: Repo) {
        if options == .standard {
            configuration.repoOptions.removeValue(forKey: repo.id)
        } else {
            configuration.repoOptions[repo.id] = options
        }
        persist()
    }

    func setScanDirectory(_ directory: URL?) {
        configuration.scanDirectory = directory
        persist()
        rescan()
    }

    func setAgentExecutable(_ executable: URL?) {
        configuration.agentExecutable = executable
        persist()
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
