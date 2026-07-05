import ForemanCore
import Foundation
import Observation

/// One repo row the menu renders. An `@Observable` class so the row's
/// `Toggle` binds to `$row.isEnabled` instead of a closure-built `Binding`;
/// flips funnel into the session's toggle intent.
@MainActor
@Observable
final class WorkerRow: Identifiable {
    let repo: ScannedRepo

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

    init(repo: ScannedRepo, isEnabled: Bool, onChange: @escaping @MainActor (WorkerRow) -> Void) {
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
    /// remain. Workers whose repo vanished from the scan are stopped (they'd
    /// otherwise keep running with no row left to control them), and saved
    /// entries for repos deleted from the current scan directory are pruned.
    /// A failed scan keeps the last good rows and reports the problem.
    func rescan() {
        do {
            let repos = try RepoDiscovery.scan(configuration.resolvedScanDirectory)
            rows = repos.map { repo in
                WorkerRow(
                    repo: repo,
                    isEnabled: configuration.enabledRepoIDs.contains(repo.id),
                ) { [weak self] row in
                    self?.applyToggle(row)
                }
            }
            issueMessage = nil

            let discovered = Set(repos.map(\.id))
            for (id, state) in supervisor.states where state.isLive && !discovered.contains(id) {
                Self.logger.info("Stopping worker for vanished repo \(id.rawValue)")
                supervisor.stop(id)
            }
            if configuration.prune(
                discovered: discovered,
                under: configuration.resolvedScanDirectory,
            ) {
                persist()
            }
        } catch {
            Self.logger.error("Repo scan failed: \(error)")
            issueMessage =
                "Couldn't scan \(configuration.resolvedScanDirectory.path): \(error.localizedDescription)"
        }
    }

    func workerState(for repo: ScannedRepo) -> WorkerSupervisor.WorkerState {
        supervisor.state(for: repo.id)
    }

    func logFileURL(for repo: ScannedRepo) -> URL {
        supervisor.logFileURL(for: repo)
    }

    // MARK: - Worker control

    /// The toggle is declarative: the switch records the *desired* state
    /// (persisted, so enabled workers restart at launch) and the status dot
    /// reports the *actual* one. Any start failure — locate or spawn — reads
    /// as `.failed` on the row with the switch still on; flipping off and on
    /// retries.
    private func applyToggle(_ row: WorkerRow) {
        // Idempotence: only act when the flip changes the desired state.
        guard row.isEnabled != configuration.enabledRepoIDs.contains(row.repo.id) else { return }

        if row.isEnabled {
            startWorker(for: row.repo)
            configuration.enabledRepoIDs.insert(row.repo.id)
        } else {
            supervisor.stop(row.repo.id)
            configuration.enabledRepoIDs.remove(row.repo.id)
        }
        persist()
    }

    /// Starts the worker for `repo`. Locating `cursor-agent` can fail before
    /// any spawn is attempted; that failure is recorded on the worker's state
    /// (and the issue banner) just like a spawn failure, so both kinds of
    /// "didn't start" look the same on the row.
    private func startWorker(for repo: ScannedRepo) {
        let executable: URL
        do {
            executable = try locator.locate(explicit: configuration.agentExecutable)
        } catch {
            Self.logger.error("Can't start worker for \(repo.name): \(error)")
            supervisor.recordStartFailure(repo.id, reason: error.localizedDescription)
            issueMessage = error.localizedDescription
            return
        }
        supervisor.start(
            repo: repo,
            options: configuration.options(for: repo.id),
            executable: executable,
        )
        issueMessage = nil
    }

    // MARK: - Options & settings

    /// Saves `options` for `repo`. Options apply on the worker's next start,
    /// so the editor is only offered while the worker is stopped.
    func updateOptions(_ options: WorkerOptions, for repo: ScannedRepo) {
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
