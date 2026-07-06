import Foundation
import Observation

/// One discovered repository in the model tree: identity, the user's
/// persisted intent (`isEnabled`, `options`), and the ``Worker`` that runs
/// its `cursor-agent` process.
///
/// The enable toggle is *declarative*: `isEnabled` records the desired state
/// (persisted, so enabled workers restart at launch) and `worker.state`
/// reports the actual one. Any start failure — locate or spawn — reads as
/// `.failed` on the worker with the toggle still on; `retry()` (or an
/// off-then-on flip) is the retry.
@MainActor
@Observable
public final class Repo: Identifiable {
    public let id: RepoID
    /// The directory name, e.g. `Stuff`.
    public let name: String
    /// Absolute file URL of the repository root.
    public let rootURL: URL
    /// The process for this repo; created eagerly, starts `.stopped`.
    public let worker: Worker

    /// Desired state. Flipping it starts/stops the worker and notifies the
    /// persistence funnel; reassigning the current value is a no-op.
    public var isEnabled: Bool {
        didSet {
            guard oldValue != isEnabled else { return }
            if isEnabled {
                startWorker()
            } else {
                worker.stop()
            }
            onPersistentChange(self)
        }
    }

    /// Worker options, applied at the next spawn (see `restart()`). Edits
    /// notify the persistence funnel; reassigning an equal value is a no-op.
    public var options: WorkerOptions {
        didSet {
            guard oldValue != options else { return }
            onPersistentChange(self)
        }
    }

    /// Whether the user pinned this repo to the top of its sidebar section.
    /// Pure presentation metadata — unlike `isEnabled` it has no worker side
    /// effect, it only notifies the persistence funnel; reassigning the
    /// current value is a no-op.
    public var isFavorite: Bool {
        didSet {
            guard oldValue != isFavorite else { return }
            onPersistentChange(self)
        }
    }

    private static let logger = ForemanLog.channel(.repo)

    private let resolveExecutable: @MainActor () throws -> URL
    private let onPersistentChange: @MainActor (Repo) -> Void

    /// - Parameters:
    ///   - scanned: The on-disk identity from ``RepoDiscovery``.
    ///   - isEnabled: The saved desired state. Assigning in `init` does not
    ///     start the worker — launch restore calls ``startIfEnabled()``.
    ///   - isFavorite: The saved favorite flag (pins the repo to the top of
    ///     its sidebar section).
    ///   - options: The saved worker options.
    ///   - worker: The repo's worker (the owning tree wires its
    ///     `onStateChange`).
    ///   - resolveExecutable: Locates the `cursor-agent` binary at start
    ///     time; a throw lands in the worker's `.failed` state.
    ///   - onPersistentChange: Invoked after every
    ///     `isEnabled`/`isFavorite`/`options` change so the owning tree can
    ///     write through and save.
    public init(
        scanned: ScannedRepo,
        isEnabled: Bool,
        isFavorite: Bool,
        options: WorkerOptions,
        worker: Worker,
        resolveExecutable: @escaping @MainActor () throws -> URL,
        onPersistentChange: @escaping @MainActor (Repo) -> Void,
    ) {
        id = scanned.id
        name = scanned.name
        rootURL = scanned.rootURL
        self.worker = worker
        self.isEnabled = isEnabled
        self.isFavorite = isFavorite
        self.options = options
        self.resolveExecutable = resolveExecutable
        self.onPersistentChange = onPersistentChange
    }

    /// Launch restore: starts the worker when the saved desired state is
    /// enabled and nothing is live yet. No-op otherwise.
    public func startIfEnabled() {
        guard isEnabled, !worker.state.isLive else { return }
        startWorker()
    }

    /// A fresh start attempt for an enabled repo sitting in `.failed` —
    /// transient, does not change the persisted desired state. No-op in any
    /// other state.
    public func retry() {
        guard isEnabled, case .failed = worker.state else { return }
        startWorker()
    }

    /// Terminates a `.running` worker and respawns it with the *current*
    /// saved options (the apply path for options edited while running) —
    /// transient, does not change the persisted desired state. The
    /// executable is resolved up front so a locate failure never kills the
    /// running worker; the respawn rides the worker's queued-restart
    /// machinery. No-op unless running.
    public func restart() {
        // Running implies enabled: disabling stops the worker synchronously,
        // so there's no running-but-disabled combination to guard against.
        guard case .running = worker.state else { return }
        let executable: URL
        do {
            executable = try resolveExecutable()
        } catch {
            Self.logger.error("Not restarting \(name): \(error)")
            return
        }
        worker.stop()
        // The worker is now .stopping, so this queues the respawn.
        worker.start(options: options, executable: executable)
    }

    private func startWorker() {
        do {
            try worker.start(options: options, executable: resolveExecutable())
        } catch {
            Self.logger.error("Can't start worker for \(name): \(error)")
            worker.recordStartFailure(reason: error.localizedDescription)
        }
    }
}
