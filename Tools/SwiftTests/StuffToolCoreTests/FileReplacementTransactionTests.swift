import Foundation
import StuffToolCore
import Testing

struct FileReplacementTransactionTests {
    @Test func commitsReplacementCreationAndDeletion() throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let fileSystem = FoundationFileSystem()
        let existing = root.appending(path: "existing")
        let removed = root.appending(path: "removed")
        let created = root.appending(path: "created")
        let stage = root.appending(path: "stage", directoryHint: .isDirectory)
        try fileSystem.createDirectory(at: stage, withIntermediateDirectories: true)
        try fileSystem.write(Data("old".utf8), to: existing, atomically: false)
        try fileSystem.write(Data("remove".utf8), to: removed, atomically: false)
        let stagedExisting = stage.appending(path: "existing")
        let stagedCreated = stage.appending(path: "created")
        try fileSystem.write(Data("new".utf8), to: stagedExisting, atomically: false)
        try fileSystem.write(Data("create".utf8), to: stagedCreated, atomically: false)

        try FileReplacementTransaction(fileSystem: fileSystem).commit(
            [
                FileReplacement(target: existing, staged: stagedExisting),
                FileReplacement(target: removed, staged: nil),
                FileReplacement(target: created, staged: stagedCreated),
            ],
            backupDirectory: root.appending(path: "backup"),
        )

        #expect(try fileSystem.read(existing) == Data("new".utf8))
        #expect(fileSystem.kind(of: removed) == .missing)
        #expect(try fileSystem.read(created) == Data("create".utf8))
    }

    @Test func restoresEveryTargetWhenACommitMoveFails() throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let base = FoundationFileSystem()
        let first = root.appending(path: "first")
        let second = root.appending(path: "second")
        let stage = root.appending(path: "stage", directoryHint: .isDirectory)
        try base.createDirectory(at: stage, withIntermediateDirectories: true)
        try base.write(Data("first-old".utf8), to: first, atomically: false)
        try base.write(Data("second-old".utf8), to: second, atomically: false)
        let stagedFirst = stage.appending(path: "first")
        let stagedSecond = stage.appending(path: "second")
        try base.write(Data("first-new".utf8), to: stagedFirst, atomically: false)
        try base.write(Data("second-new".utf8), to: stagedSecond, atomically: false)
        let faulting = FailingMoveFileSystem(base: base, failingMove: 4)

        #expect(throws: (any Error).self) {
            try FileReplacementTransaction(fileSystem: faulting).commit(
                [
                    FileReplacement(target: first, staged: stagedFirst),
                    FileReplacement(target: second, staged: stagedSecond),
                ],
                backupDirectory: root.appending(path: "backup"),
            )
        }

        #expect(try base.read(first) == Data("first-old".utf8))
        #expect(try base.read(second) == Data("second-old".utf8))
    }
}

private final class FailingMoveFileSystem: FileSystem, @unchecked Sendable {
    private let base: FoundationFileSystem
    private let failingMove: Int
    private var moveCount = 0

    init(base: FoundationFileSystem, failingMove: Int) {
        self.base = base
        self.failingMove = failingMove
    }

    func kind(of url: URL) -> FileItemKind {
        base.kind(of: url)
    }

    func contents(of directory: URL) throws -> [URL] {
        try base.contents(of: directory)
    }

    func copyItem(at source: URL, to destination: URL) throws {
        try base.copyItem(at: source, to: destination)
    }

    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {
        try base.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
    }

    func moveItem(at source: URL, to destination: URL) throws {
        moveCount += 1
        if moveCount == failingMove { throw InjectedMoveFailure() }
        try base.moveItem(at: source, to: destination)
    }

    func removeItem(at url: URL) throws {
        try base.removeItem(at: url)
    }

    func read(_ url: URL) throws -> Data {
        try base.read(url)
    }

    func write(_ data: Data, to url: URL, atomically: Bool) throws {
        try base.write(data, to: url, atomically: atomically)
    }

    func setPosixPermissions(_ permissions: Int, at url: URL) throws {
        try base.setPosixPermissions(permissions, at: url)
    }
}

private struct InjectedMoveFailure: Error {}
