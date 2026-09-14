import CryptoKit
import Foundation

public struct GitHubRepository: Hashable, Codable, Sendable {
    public let owner: String
    public let name: String

    public init(owner: String, name: String) throws {
        self.owner = owner
        self.name = name
        try validate()
    }

    func validate() throws {
        for value in [owner, name] {
            guard !value.isEmpty, value != ".", value != "..",
                  value
                  .allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) })
            else {
                throw GitHubError.invalidIdentifier
            }
        }
    }
}

public struct GitHubObjectID: Hashable, Codable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) throws {
        self.rawValue = rawValue
        try validate()
    }

    func validate() throws {
        guard rawValue.count == 40, rawValue.allSatisfy({ "0123456789abcdef".contains($0) }) else {
            throw GitHubError.invalidIdentifier
        }
    }
}

public struct GitHubRepositoryPath: Hashable, Codable, Sendable, Comparable {
    public let rawValue: String

    public init(_ rawValue: String) throws {
        self.rawValue = rawValue
        try validate()
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    func validate() throws {
        let components = rawValue.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty,
              components
              .allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && $0.lowercased() != ".git" }),
              !rawValue.contains("\\"),
              !rawValue.unicodeScalars
              .contains(where: { CharacterSet.controlCharacters.contains($0) })
        else {
            throw GitHubError.invalidPath
        }
    }
}

public enum GitHubTextFileMode: String, Codable, Sendable {
    case regular = "100644"
    case executable = "100755"
}

public struct GitHubSourceFile: Equatable, Codable, Sendable {
    public let path: GitHubRepositoryPath
    public let text: String
    public let mode: GitHubTextFileMode

    public init(path: GitHubRepositoryPath, text: String, mode: GitHubTextFileMode) {
        self.path = path
        self.text = text
        self.mode = mode
    }
}

/// The source that produced the installed app. Dirty files are evidence, never implicit repository
/// edits.
public struct GitHubInstalledSource: Codable, Sendable {
    public let buildIdentity: String
    public let isDirty: Bool
    public let files: [GitHubSourceFile]

    public init(buildIdentity: String, isDirty: Bool, files: [GitHubSourceFile]) {
        self.buildIdentity = buildIdentity
        self.isDirty = isDirty
        self.files = files
    }
}

/// An immutable commit and its selected text files. The base tree preserves all unselected
/// repository files.
public struct GitHubRepositorySnapshot: Codable, Sendable {
    public let repository: GitHubRepository
    public let branch: String
    public let commit: GitHubObjectID
    public let tree: GitHubObjectID
    public let knownPaths: Set<GitHubRepositoryPath>
    public let files: [GitHubSourceFile]

    public init(
        repository: GitHubRepository,
        branch: String,
        commit: GitHubObjectID,
        tree: GitHubObjectID,
        knownPaths: Set<GitHubRepositoryPath>,
        files: [GitHubSourceFile],
    ) throws {
        self.repository = repository
        self.branch = branch
        self.commit = commit
        self.tree = tree
        self.knownPaths = knownPaths
        self.files = files
        try validate()
    }

    func validate() throws {
        try repository.validate()
        try commit.validate()
        try tree.validate()
        try GitHubBranch.validate(branch)
        guard Set(files.map(\.path)).count == files.count else { throw GitHubError.invalidResponse }
        for path in knownPaths {
            try path.validate()
        }
        for file in files {
            try file.path.validate()
            guard knownPaths.contains(file.path) else { throw GitHubError.invalidResponse }
        }
    }
}

enum GitHubBranch {
    static func validate(_ value: String) throws {
        guard !value.isEmpty, !value.hasPrefix("-"), !value.hasSuffix("."), !value.contains(".."),
              !value.contains("@{"), value != "@",
              !value.unicodeScalars
              .contains(where: {
                  CharacterSet.controlCharacters.contains($0) || " ~^:?*[\\".unicodeScalars
                      .contains($0)
              }),
              value.split(separator: "/", omittingEmptySubsequences: false)
              .allSatisfy({ !$0.isEmpty && !$0.hasPrefix(".") && !$0.hasSuffix(".lock") })
        else {
            throw GitHubError.invalidIdentifier
        }
    }
}

/// A patch entry preserves both sides so approval cannot silently change its reviewed contents.
public struct GitHubFileChange: Equatable, Codable, Sendable {
    public let path: GitHubRepositoryPath
    public let before: GitHubSourceFile?
    public let after: GitHubSourceFile?

    public init(
        path: GitHubRepositoryPath,
        before: GitHubSourceFile?,
        after: GitHubSourceFile?,
    ) throws {
        self.path = path
        self.before = before
        self.after = after
        try validate()
    }

    func validate() throws {
        try path.validate()
        guard before != after, before?.path == nil || before?.path == path,
              after?.path == nil || after?.path == path
        else {
            throw GitHubError.emptyPatch
        }
    }
}

/// An editable value workspace. Only explicit edits enter a proposal; the installed source remains
/// untouched.
public struct GitHubSourceWorkspace: Sendable {
    public let installedSource: GitHubInstalledSource
    public let repositoryBase: GitHubRepositorySnapshot
    private var changes: [GitHubRepositoryPath: GitHubFileChange] = [:]

    public init(installedSource: GitHubInstalledSource, repositoryBase: GitHubRepositorySnapshot) {
        self.installedSource = installedSource
        self.repositoryBase = repositoryBase
    }

    public var patch: [GitHubFileChange] {
        changes.values.sorted { $0.path < $1.path }
    }

    public func file(at path: GitHubRepositoryPath) -> GitHubSourceFile? {
        if let change = changes[path] { return change.after }
        return repositoryBase.files.first { $0.path == path }
    }

    public mutating func setText(
        _ text: String,
        at path: GitHubRepositoryPath,
        mode: GitHubTextFileMode,
    ) throws {
        try path.validate()
        let before = repositoryBase.files.first { $0.path == path }
        guard before != nil || !repositoryBase.knownPaths.contains(path)
        else { throw GitHubError.missingBaseFile }
        let after = GitHubSourceFile(path: path, text: text, mode: mode)
        if before == after {
            changes[path] = nil
        } else {
            changes[path] = try GitHubFileChange(path: path, before: before, after: after)
        }
    }

    public mutating func remove(at path: GitHubRepositoryPath) throws {
        try path.validate()
        if let before = repositoryBase.files.first(where: { $0.path == path }) {
            changes[path] = try GitHubFileChange(path: path, before: before, after: nil)
        } else if changes[path] != nil {
            changes[path] = nil
        } else {
            throw GitHubError.missingBaseFile
        }
    }

    public mutating func discardChanges() {
        changes.removeAll()
    }
}

enum GitHubFingerprint {
    static func value(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try SHA256.hash(data: encoder.encode(value)).map { String(format: "%02x", $0) }
            .joined()
    }
}
