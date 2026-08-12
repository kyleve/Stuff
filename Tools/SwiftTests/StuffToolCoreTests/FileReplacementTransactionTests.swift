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
        let faulting = MoveFaultFileSystem(base: base, failingMove: 4)

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

    @Test func preservesAndReportsBackupsWhenRollbackFails() throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let base = FoundationFileSystem()
        let target = root.appending(path: "target")
        let staged = root.appending(path: "staged")
        let backup = root.appending(path: "backup", directoryHint: .isDirectory)
        try base.write(Data("old".utf8), to: target, atomically: false)
        try base.write(Data("new".utf8), to: staged, atomically: false)
        let faulting = MoveFaultFileSystem(base: base, failingMoves: [2, 3])

        do {
            try FileReplacementTransaction(fileSystem: faulting).commit(
                [FileReplacement(target: target, staged: staged)],
                backupDirectory: backup,
            )
            Issue.record("expected rollback failure")
        } catch let failure as FileReplacementTransactionFailure {
            guard case let .rollbackFailed(_, _, recoveryDirectory) = failure else {
                Issue.record("unexpected transaction failure: \(failure)")
                return
            }
            #expect(recoveryDirectory == backup)
            #expect(failure.description.contains(backup.path))
        } catch {
            Issue.record("unexpected error: \(error)")
        }

        #expect(base.kind(of: target) == .missing)
        #expect(try base.read(backup.appending(path: "0")) == Data("old".utf8))
    }
}
