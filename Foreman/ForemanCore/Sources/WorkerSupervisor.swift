import Foundation
import Observation

/// Owns one `cursor-agent worker start` process per enabled repository:
/// spawning, log capture, termination bookkeeping, and the sleep assertion
/// that keeps the machine awake while any worker is live.
///
/// Each worker's stdout+stderr stream to `<logDirectory>/<repo name>.log`.
/// State per repo is a single ``WorkerState`` enum, so "running", "who asked
/// it to stop", and "why it died" can't drift into contradictory flags.
@MainActor
@Observable
public final class WorkerSupervisor {
    public enum WorkerState: Equatable, Sendable {
        case stopped
        case starting
        case running(pid: Int32)
        /// Stop was requested; the process hasn't exited yet.
        case stopping
        case failed(reason: String)

        /// Whether a process is (or is about to be) alive for this state.
        public var isLive: Bool {
            switch self {
                case .starting, .running, .stopping: true
                case .stopped, .failed: false
            }
        }
    }

    /// Current state per repo. Repos never started are absent — read through
    /// ``state(for:)``, which maps absence to `.stopped`.
    public private(set) var states: [RepoID: WorkerState] = [:]

    /// Whether the idle-sleep assertion is currently held.
    public var isInhibitingSleep: Bool {
        sleepInhibitor.isActive
    }

    /// Where worker logs land: `~/Library/Logs/Foreman`.
    public static var defaultLogDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Foreman", isDirectory: true)
    }

    private struct Handle {
        let process: Process
        let logHandle: FileHandle
        var stopRequested = false
    }

    private static let logger = ForemanLog.channel(.workerSupervisor)

    private let logDirectory: URL
    private let sleepInhibitor: SleepInhibitor
    @ObservationIgnored private var handles: [RepoID: Handle] = [:]

    public convenience init(logDirectory: URL) {
        self.init(logDirectory: logDirectory, sleepInhibitor: SleepInhibitor())
    }

    @_spi(Testing)
    public init(logDirectory: URL, sleepInhibitor: SleepInhibitor) {
        self.logDirectory = logDirectory
        self.sleepInhibitor = sleepInhibitor
    }

    public func state(for id: RepoID) -> WorkerState {
        states[id] ?? .stopped
    }

    /// The log file worker output for `repo` is appended to.
    public func logFileURL(for repo: Repo) -> URL {
        logDirectory.appendingPathComponent("\(repo.name).log")
    }

    /// Spawns a worker for `repo`. A start while the worker is already live is
    /// ignored; starting over a `.failed` state retries. A spawn failure lands
    /// in `.failed` (and the log) rather than throwing — the state is the
    /// caller-observable result either way.
    public func start(repo: Repo, options: WorkerOptions, executable: URL) {
        let id = repo.id
        let current = state(for: id)
        guard !current.isLive else {
            Self.logger.debug("Ignoring start for \(repo.name): worker is already live")
            return
        }
        states[id] = .starting
        updateSleepInhibition()

        let arguments = options.arguments(workerDirectory: repo.rootURL)
        do {
            let logHandle = try openLogFile(for: repo)
            let argv = ([executable.path] + arguments).joined(separator: " ")
            try logHandle.write(contentsOf: Data(
                "\n=== Foreman: starting worker (\(Date().ISO8601Format())): \(argv)\n".utf8,
            ))

            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.currentDirectoryURL = repo.rootURL
            process.standardOutput = logHandle
            process.standardError = logHandle
            process.terminationHandler = { [weak self] process in
                let status = process.terminationStatus
                let reason = process.terminationReason
                Task { @MainActor [weak self] in
                    self?.workerDidTerminate(id, status: status, reason: reason)
                }
            }
            try process.run()

            handles[id] = Handle(process: process, logHandle: logHandle)
            states[id] = .running(pid: process.processIdentifier)
            Self.logger.info(
                "Started worker for \(repo.name) (pid \(process.processIdentifier))",
            )
        } catch {
            states[id] = .failed(reason: error.localizedDescription)
            Self.logger.error("Failed to start worker for \(repo.name): \(error)")
        }
        updateSleepInhibition()
    }

    /// Requests termination (SIGTERM); the state moves to `.stopped` once the
    /// process actually exits. No-ops when nothing is live for `id`.
    public func stop(_ id: RepoID) {
        guard let handle = handles[id], !handle.stopRequested else { return }
        handles[id]?.stopRequested = true
        states[id] = .stopping
        handle.process.terminate()
        Self.logger.info("Stopping worker for \(id.rawValue)")
    }

    /// Stops every live worker — the app's quit path.
    public func stopAll() {
        for id in Array(handles.keys) {
            stop(id)
        }
    }

    private func workerDidTerminate(
        _ id: RepoID,
        status: Int32,
        reason: Process.TerminationReason,
    ) {
        guard let handle = handles.removeValue(forKey: id) else { return }

        let endState: WorkerState = if handle.stopRequested {
            .stopped
        } else {
            switch reason {
                case .exit:
                    // A clean self-exit (e.g. the CLI released the worker) is a
                    // stop, not a failure.
                    status == 0 ? .stopped : .failed(reason: "Exited with code \(status)")
                case .uncaughtSignal:
                    .failed(reason: "Terminated by signal \(status)")
                @unknown default:
                    .failed(reason: "Terminated (unknown reason, status \(status))")
            }
        }

        do {
            try handle.logHandle.write(contentsOf: Data(
                "=== Foreman: worker exited (\(Date().ISO8601Format())): status \(status)\n".utf8,
            ))
            try handle.logHandle.close()
        } catch {
            Self.logger.warning("Couldn't finalize worker log for \(id.rawValue): \(error)")
        }

        states[id] = endState
        switch endState {
            case .stopped:
                Self.logger.info("Worker for \(id.rawValue) stopped")
            case let .failed(reason):
                Self.logger.error("Worker for \(id.rawValue) failed: \(reason)")
            case .starting, .running, .stopping:
                assertionFailure("Termination resolved to a live state")
        }
        updateSleepInhibition()
    }

    private func updateSleepInhibition() {
        sleepInhibitor.setActive(
            states.values.contains(where: \.isLive),
            reason: "Cursor agent workers are running",
        )
    }

    private func openLogFile(for repo: Repo) throws -> FileHandle {
        try FileManager.default.createDirectory(
            at: logDirectory,
            withIntermediateDirectories: true,
        )
        let url = logFileURL(for: repo)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        return handle
    }
}
