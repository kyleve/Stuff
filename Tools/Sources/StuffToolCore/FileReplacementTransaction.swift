import Foundation

public struct FileReplacement: Equatable, Sendable {
    public let target: URL
    public let staged: URL?

    public init(target: URL, staged: URL?) {
        self.target = target
        self.staged = staged
    }
}

public enum FileReplacementTransactionFailure: Error, CustomStringConvertible, Sendable {
    case rollbackFailed(commit: String, rollback: String)

    public var description: String {
        switch self {
            case let .rollbackFailed(commit, rollback):
                "file commit failed (\(commit)); rollback also failed (\(rollback))"
        }
    }
}

/// Atomically swaps staged files or directories into place with reverse-order rollback.
public struct FileReplacementTransaction: Sendable {
    private struct AppliedReplacement {
        let replacement: FileReplacement
        let backup: URL?
        let installedStagedItem: Bool
    }

    private let fileSystem: any FileSystem

    public init(fileSystem: any FileSystem) {
        self.fileSystem = fileSystem
    }

    public func commit(
        _ replacements: [FileReplacement],
        backupDirectory: URL,
    ) throws {
        try fileSystem.createDirectory(
            at: backupDirectory,
            withIntermediateDirectories: true,
        )
        var applied: [AppliedReplacement] = []
        do {
            for (index, replacement) in replacements.enumerated() {
                let backup: URL?
                if fileSystem.kind(of: replacement.target) == .missing {
                    backup = nil
                } else {
                    let value = backupDirectory.appending(path: String(index))
                    try fileSystem.moveItem(at: replacement.target, to: value)
                    backup = value
                }

                var installed = false
                do {
                    if let staged = replacement.staged {
                        try fileSystem.moveItem(at: staged, to: replacement.target)
                        installed = true
                    }
                } catch {
                    applied.append(
                        AppliedReplacement(
                            replacement: replacement,
                            backup: backup,
                            installedStagedItem: installed,
                        ),
                    )
                    throw error
                }
                applied.append(
                    AppliedReplacement(
                        replacement: replacement,
                        backup: backup,
                        installedStagedItem: installed,
                    ),
                )
            }
        } catch {
            let commitError = error
            do {
                try rollback(applied.reversed())
            } catch {
                throw FileReplacementTransactionFailure.rollbackFailed(
                    commit: String(describing: commitError),
                    rollback: String(describing: error),
                )
            }
            throw commitError
        }
    }

    private func rollback(_ applied: ReversedCollection<[AppliedReplacement]>) throws {
        for entry in applied {
            if entry.installedStagedItem,
               fileSystem.kind(of: entry.replacement.target) != .missing
            {
                try fileSystem.removeItem(at: entry.replacement.target)
            }
            if let backup = entry.backup {
                try fileSystem.moveItem(at: backup, to: entry.replacement.target)
            }
        }
    }
}
