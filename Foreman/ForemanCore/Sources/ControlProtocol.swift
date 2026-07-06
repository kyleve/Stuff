import Foundation

// The wire contract for Foreman's local control socket: newline-delimited
// JSON, one ``ControlRequest`` per line, one ``ControlResponse`` back.
//
// The DTOs use plain `String` ids/paths (not ``RepoID``/`URL`) so the
// hand-written TypeScript client (`Foreman/foreman-mcp`) can speak the same
// JSON without guessing Swift's encoding of wrapper types.

// MARK: - Requests

/// A command sent to Foreman over the control socket.
public enum ControlRequest: Sendable, Equatable {
    /// Report the scan directory and every known repo with its worker state.
    case describe
    /// Adopt the copy at `path` (recording its provenance) and start its
    /// worker. `path` must be an immediate subdirectory of the scan directory.
    case adopt(path: String, provenance: CopyProvenanceDTO)
    /// Stop the worker for the copy at `path` and remove it from disk. Only
    /// copies Foreman created (with recorded provenance) can be removed.
    case removeCopy(path: String)
}

extension ControlRequest: Codable {
    private enum CodingKeys: String, CodingKey {
        case command, path, provenance
    }

    private enum Command: String, Codable {
        case describe, adopt, removeCopy
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Command.self, forKey: .command) {
            case .describe:
                self = .describe
            case .adopt:
                self = try .adopt(
                    path: container.decode(String.self, forKey: .path),
                    provenance: container.decode(CopyProvenanceDTO.self, forKey: .provenance),
                )
            case .removeCopy:
                self = try .removeCopy(path: container.decode(String.self, forKey: .path))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
            case .describe:
                try container.encode(Command.describe, forKey: .command)
            case let .adopt(path, provenance):
                try container.encode(Command.adopt, forKey: .command)
                try container.encode(path, forKey: .path)
                try container.encode(provenance, forKey: .provenance)
            case let .removeCopy(path):
                try container.encode(Command.removeCopy, forKey: .command)
                try container.encode(path, forKey: .path)
        }
    }
}

// MARK: - Responses

/// Foreman's reply to a ``ControlRequest``. On the wire, successes carry
/// `"ok": true` plus a `"kind"` discriminator; failures carry `"ok": false`
/// and an `"error"` message.
public enum ControlResponse: Sendable, Equatable {
    case describe(DescribeResultDTO)
    case repo(RepoStatusDTO)
    case removed(path: String)
    case failure(message: String)
}

extension ControlResponse: Codable {
    private enum CodingKeys: String, CodingKey {
        case ok, kind, describe, repo, path, error
    }

    private enum Kind: String, Codable {
        case describe, repo, removed
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Bool.self, forKey: .ok) else {
            self = try .failure(message: container.decode(String.self, forKey: .error))
            return
        }
        switch try container.decode(Kind.self, forKey: .kind) {
            case .describe:
                self = try .describe(container.decode(DescribeResultDTO.self, forKey: .describe))
            case .repo:
                self = try .repo(container.decode(RepoStatusDTO.self, forKey: .repo))
            case .removed:
                self = try .removed(path: container.decode(String.self, forKey: .path))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
            case let .describe(result):
                try container.encode(true, forKey: .ok)
                try container.encode(Kind.describe, forKey: .kind)
                try container.encode(result, forKey: .describe)
            case let .repo(status):
                try container.encode(true, forKey: .ok)
                try container.encode(Kind.repo, forKey: .kind)
                try container.encode(status, forKey: .repo)
            case let .removed(path):
                try container.encode(true, forKey: .ok)
                try container.encode(Kind.removed, forKey: .kind)
                try container.encode(path, forKey: .path)
            case let .failure(message):
                try container.encode(false, forKey: .ok)
                try container.encode(message, forKey: .error)
        }
    }
}

// MARK: - DTOs

/// A copy's provenance in wire form: `kind` is `"worktree"` or `"clone"`,
/// `parentRepoID` is the parent repo's path.
public struct CopyProvenanceDTO: Codable, Equatable, Sendable {
    public var kind: String
    public var parentRepoID: String
    public var branch: String

    public init(kind: String, parentRepoID: String, branch: String) {
        self.kind = kind
        self.parentRepoID = parentRepoID
        self.branch = branch
    }

    public init(_ provenance: CopyProvenance) {
        self.init(
            kind: provenance.kind.rawValue,
            parentRepoID: provenance.parentRepoID.rawValue,
            branch: provenance.branch,
        )
    }

    /// Parses this wire value into a ``CopyProvenance``, throwing
    /// ``ControlError/invalidProvenanceKind(_:)`` for an unrecognized `kind`.
    public func model() throws -> CopyProvenance {
        guard let kind = CopyProvenance.Kind(rawValue: kind) else {
            throw ControlError.invalidProvenanceKind(kind)
        }
        return CopyProvenance(
            kind: kind,
            parentRepoID: RepoID(rawValue: parentRepoID),
            branch: branch,
        )
    }
}

/// One repository's status as reported over the control socket.
public struct RepoStatusDTO: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var path: String
    public var enabled: Bool
    /// `"stopped"`, `"running"`, `"stopping"`, or `"failed"`.
    public var workerState: String
    public var pid: Int?
    public var failureReason: String?
    public var provenance: CopyProvenanceDTO?

    public init(
        id: String,
        name: String,
        path: String,
        enabled: Bool,
        workerState: String,
        pid: Int?,
        failureReason: String?,
        provenance: CopyProvenanceDTO?,
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.enabled = enabled
        self.workerState = workerState
        self.pid = pid
        self.failureReason = failureReason
        self.provenance = provenance
    }
}

/// The `describe` result: the scan directory plus every known repo.
public struct DescribeResultDTO: Codable, Equatable, Sendable {
    public var scanDirectory: String
    public var repos: [RepoStatusDTO]

    public init(scanDirectory: String, repos: [RepoStatusDTO]) {
        self.scanDirectory = scanDirectory
        self.repos = repos
    }
}

@MainActor
extension RepoStatusDTO {
    /// Snapshots a live ``Repo`` into its wire form.
    public init(repo: Repo) {
        let workerState: String
        var pid: Int?
        var failureReason: String?
        switch repo.worker.state {
            case .stopped:
                workerState = "stopped"
            case let .running(runningPID, _):
                workerState = "running"
                pid = Int(runningPID)
            case .stopping:
                workerState = "stopping"
            case let .failed(reason):
                workerState = "failed"
                failureReason = reason
        }
        self.init(
            id: repo.id.rawValue,
            name: repo.name,
            path: repo.rootURL.path,
            enabled: repo.isEnabled,
            workerState: workerState,
            pid: pid,
            failureReason: failureReason,
            provenance: repo.provenance.map(CopyProvenanceDTO.init),
        )
    }
}

// MARK: - Errors

/// A control operation that couldn't be carried out. All cases are
/// user-recoverable and carry a localized description surfaced to the caller
/// (the MCP over the socket, or the Foreman UI's Remove action).
public enum ControlError: Error, LocalizedError, Equatable {
    /// The path isn't an immediate subdirectory of the scan directory.
    case pathNotUnderScanDirectory(path: String, scanDirectory: String)
    /// The path isn't a git working copy.
    case notAGitRepository(path: String)
    /// No repo with that path is known after a rescan.
    case repoNotFound(path: String)
    /// The path has no recorded provenance, so it isn't a Foreman-made copy.
    case notACopy(path: String)
    /// The provenance `kind` string wasn't `"worktree"` or `"clone"`.
    case invalidProvenanceKind(String)
    /// The worker didn't stop in time to remove the copy safely.
    case workerDidNotStop(path: String)
    /// The underlying removal (git or Trash) failed; carries its reason.
    case removeFailed(reason: String)

    public var errorDescription: String? {
        switch self {
            case let .pathNotUnderScanDirectory(path, scanDirectory):
                String(localized: .controlNotUnderScanDirectory(path: path, scan: scanDirectory))
            case let .notAGitRepository(path):
                String(localized: .controlNotAGitRepo(path: path))
            case let .repoNotFound(path):
                String(localized: .controlRepoNotFound(path: path))
            case let .notACopy(path):
                String(localized: .controlNotACopy(path: path))
            case let .invalidProvenanceKind(kind):
                String(localized: .controlInvalidProvenanceKind(kind: kind))
            case .workerDidNotStop:
                String(localized: .controlWorkerDidNotStop)
            case let .removeFailed(reason):
                String(localized: .controlRemoveFailed(error: reason))
        }
    }
}
