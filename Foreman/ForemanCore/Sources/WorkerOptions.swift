import Foundation

/// Per-repository options for a `cursor-agent worker` process, mirroring the
/// CLI flags one-to-one. ``arguments(workerDirectory:)`` renders the argv so
/// the mapping lives in exactly one place.
public struct WorkerOptions: Codable, Equatable, Sendable {
    /// One `--label key=value` pair.
    public struct Label: Codable, Hashable, Sendable {
        public var key: String
        public var value: String

        public init(key: String, value: String) {
            self.key = key
            self.value = value
        }

        /// The `key=value` form the CLI expects.
        public var argumentValue: String {
            "\(key)=\(value)"
        }
    }

    /// How Cursor assigns agents to this worker. Pool registration and the
    /// pool's name only exist together, so they are one case, not two fields.
    public enum Assignment: Codable, Equatable, Sendable {
        /// Multiple concurrent agents may share the worker (CLI default).
        case shared
        /// One cloud agent claims the worker at a time (`--pool`), registered
        /// under `name` (`--pool-name`). An empty name defers to the CLI's own
        /// default pool ("default").
        case pool(name: String)
    }

    /// Custom display name (`--name`); `nil` defers to the CLI default (the
    /// machine hostname).
    public var displayName: String?
    public var assignment: Assignment
    public var labels: [Label]
    /// Seconds the worker may sit idle before it can be released
    /// (`--idle-release-timeout`); `0` disables idle-based release, matching
    /// the CLI's own zero default.
    public var idleReleaseTimeoutSeconds: Int
    /// Verbose startup logs (`--verbose` on the `start` subcommand).
    public var verbose: Bool

    public init(
        displayName: String?,
        assignment: Assignment,
        labels: [Label],
        idleReleaseTimeoutSeconds: Int,
        verbose: Bool,
    ) {
        self.displayName = displayName
        self.assignment = assignment
        self.labels = labels
        self.idleReleaseTimeoutSeconds = idleReleaseTimeoutSeconds
        self.verbose = verbose
    }

    /// The defaults a repo starts with: CLI-default everything.
    public static let standard = WorkerOptions(
        displayName: nil,
        assignment: .shared,
        labels: [],
        idleReleaseTimeoutSeconds: 0,
        verbose: false,
    )

    /// Arguments passed to the `cursor-agent` executable to start a worker for
    /// the repository at `workerDirectory`. Worker-level flags precede the
    /// `start` subcommand; `--verbose` belongs to `start` itself.
    public func arguments(workerDirectory: URL) -> [String] {
        var arguments = ["worker", "--worker-dir", workerDirectory.path]
        if let displayName {
            arguments += ["--name", displayName]
        }
        switch assignment {
            case .shared:
                break
            case let .pool(name):
                arguments.append("--pool")
                if !name.isEmpty {
                    arguments += ["--pool-name", name]
                }
        }
        for label in labels {
            arguments += ["--label", label.argumentValue]
        }
        if idleReleaseTimeoutSeconds > 0 {
            arguments += ["--idle-release-timeout", String(idleReleaseTimeoutSeconds)]
        }
        arguments.append("start")
        if verbose {
            arguments.append("--verbose")
        }
        return arguments
    }
}
