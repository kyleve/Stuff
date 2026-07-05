import Foundation
import Observation

/// One repository's `cursor-agent worker start` process: spawning, log
/// capture, termination bookkeeping, and the queued-restart machinery.
///
/// A `Worker` is created per repo (by the repo tree) and lives as long as its
/// repo does. All state is a single ``State`` enum, so "running", "who asked
/// it to stop", and "why it died" can't drift into contradictory flags.
/// stdout+stderr stream to `<logDirectory>/<repo name>.log`.
@MainActor
@Observable
public final class Worker {
    public enum State: Equatable, Sendable {
        case stopped
        /// No `.starting`: spawning is synchronous on the main actor, so a
        /// start resolves to `.running` or `.failed` before anyone can
        /// observe an in-between state. `since` is the spawn time, for
        /// uptime display.
        case running(pid: Int32, since: Date)
        /// Stop was requested; the process hasn't exited yet. A start
        /// requested in this window can't spawn immediately (the exiting
        /// process still owns the log file), so it queues a restart —
        /// `restartPending` — applied when the exit lands.
        case stopping(restartPending: Bool)
        case failed(reason: String)

        /// Whether a process is alive for this state.
        public var isLive: Bool {
            switch self {
                case .running, .stopping: true
                case .stopped, .failed: false
            }
        }
    }

    /// Current state. Every transition invokes the injected `onStateChange`
    /// (after the mutation lands), which the owning tree uses to recompute
    /// cross-worker concerns like sleep inhibition.
    public private(set) var state: State = .stopped {
        didSet {
            guard oldValue != state else { return }
            onStateChange()
        }
    }

    /// Where this worker's output is appended: `<logDirectory>/<name>.log`.
    public let logFileURL: URL

    private struct Handle {
        let process: Process
        let logHandle: FileHandle
        var stopRequested = false
    }

    /// A start requested while the previous process was still stopping,
    /// replayed (with the arguments captured at request time) once the old
    /// process exits.
    private struct PendingStart {
        let options: WorkerOptions
        let executable: URL
    }

    private static let logger = ForemanLog.channel(.worker)

    private let name: String
    private let workerDirectory: URL
    private let onStateChange: @MainActor () -> Void
    @ObservationIgnored private var handle: Handle?
    @ObservationIgnored private var pendingStart: PendingStart?

    /// - Parameters:
    ///   - name: The repo's display name; also names the log file.
    ///   - workerDirectory: The repo root the process runs in.
    ///   - logDirectory: Where the log file lives (created on first start).
    ///   - onStateChange: Invoked on the main actor after every `state`
    ///     transition (never for a same-value reassignment).
    public init(
        name: String,
        workerDirectory: URL,
        logDirectory: URL,
        onStateChange: @escaping @MainActor () -> Void,
    ) {
        self.name = name
        self.workerDirectory = workerDirectory
        logFileURL = logDirectory.appendingPathComponent("\(name).log")
        self.onStateChange = onStateChange
    }

    /// Spawns the worker process. A start while already running is ignored;
    /// a start while `.stopping` queues a restart applied when the exit
    /// lands; starting over a `.failed` state retries. A spawn failure lands
    /// in `.failed` (and the log) rather than throwing — the state is the
    /// caller-observable result either way.
    public func start(options: WorkerOptions, executable: URL) {
        switch state {
            case .running:
                Self.logger.debug("Ignoring start for \(name): worker is already running")
                return
            case .stopping:
                pendingStart = PendingStart(options: options, executable: executable)
                state = .stopping(restartPending: true)
                Self.logger.info("Queued restart for \(name): worker is still stopping")
                return
            case .stopped, .failed:
                break
        }

        let arguments = options.arguments(workerDirectory: workerDirectory)
        do {
            let logHandle = try openLogFile()
            let argv = ([executable.path] + arguments).joined(separator: " ")
            try logHandle.write(contentsOf: Data(
                "\n=== Foreman: starting worker (\(Date().ISO8601Format())): \(argv)\n".utf8,
            ))

            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.currentDirectoryURL = workerDirectory
            process.standardOutput = logHandle
            process.standardError = logHandle
            process.terminationHandler = { [weak self] process in
                let status = process.terminationStatus
                let reason = process.terminationReason
                Task { @MainActor [weak self] in
                    self?.processDidTerminate(status: status, reason: reason)
                }
            }
            try process.run()

            handle = Handle(process: process, logHandle: logHandle)
            state = .running(pid: process.processIdentifier, since: Date())
            Self.logger.info("Started worker for \(name) (pid \(process.processIdentifier))")
        } catch {
            state = .failed(reason: error.localizedDescription)
            Self.logger.error("Failed to start worker for \(name): \(error)")
        }
    }

    /// Records a start attempt that failed before any spawn (e.g. the
    /// `cursor-agent` executable couldn't be located), so the worker reads
    /// `.failed` with a reason like any other start failure instead of an
    /// unexplained `.stopped`. Ignored (with a warning) while live — a
    /// pre-spawn failure can't override a process that exists.
    public func recordStartFailure(reason: String) {
        guard !state.isLive else {
            Self.logger.warning("Ignoring start failure for \(name): a worker is still live")
            return
        }
        state = .failed(reason: reason)
        Self.logger.error("Worker for \(name) couldn't start: \(reason)")
    }

    /// Requests termination (SIGTERM); the state moves to `.stopped` once
    /// the process actually exits. A stop while a restart is queued cancels
    /// the restart. With nothing live, a stop acknowledges a `.failed`
    /// state — "make it not running" includes clearing a failure the user
    /// has switched off — and is otherwise a no-op.
    public func stop() {
        guard handle != nil else {
            if case .failed = state {
                state = .stopped
                Self.logger.info("Cleared failure for \(name): worker was switched off")
            }
            return
        }
        if pendingStart != nil {
            // Termination was already requested; just drop the queued restart.
            pendingStart = nil
            state = .stopping(restartPending: false)
            Self.logger.info("Cancelled queued restart for \(name)")
            return
        }
        guard handle?.stopRequested == false else { return }
        handle?.stopRequested = true
        state = .stopping(restartPending: false)
        handle?.process.terminate()
        Self.logger.info("Stopping worker for \(name)")
    }

    private func processDidTerminate(status: Int32, reason: Process.TerminationReason) {
        guard let handle else { return }
        self.handle = nil

        let endState: State = if handle.stopRequested {
            .stopped
        } else {
            switch reason {
                case .exit:
                    // A clean self-exit (e.g. the CLI released the worker) is
                    // a stop, not a failure.
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
            Self.logger.warning("Couldn't finalize worker log for \(name): \(error)")
        }

        state = endState
        switch endState {
            case .stopped:
                Self.logger.info("Worker for \(name) stopped")
            case let .failed(reason):
                Self.logger.error("Worker for \(name) failed: \(reason)")
            case .running, .stopping:
                assertionFailure("Termination resolved to a live state")
        }

        if let pending = pendingStart {
            pendingStart = nil
            Self.logger.info("Applying queued restart for \(name)")
            start(options: pending.options, executable: pending.executable)
        }
    }

    private func openLogFile() throws -> FileHandle {
        try FileManager.default.createDirectory(
            at: logFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: logFileURL)
        try handle.seekToEnd()
        return handle
    }
}
