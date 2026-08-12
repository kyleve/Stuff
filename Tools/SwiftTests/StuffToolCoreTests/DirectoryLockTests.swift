import Foundation
import StuffToolCore
import Testing

struct DirectoryLockTests {
    @Test func clearsAStaleOwnedLockAndReleasesIt() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let lockURL = root.appending(path: "simulator.lock", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: lockURL, withIntermediateDirectories: true)
        try Data("99\n".utf8).write(to: lockURL.appending(path: "pid"))
        let terminal = MemoryTerminal()
        var lock = DirectoryLock(
            directory: lockURL,
            processID: 42,
            fileSystem: FoundationFileSystem(),
            clock: ImmediateClock(),
            processInspector: StubProcessInspector(runningProcessIDs: []),
            warning: { message in try await terminal.write(message, to: .standardError) },
        )

        try await lock.acquire()

        let pid = try String(contentsOf: lockURL.appending(path: "pid"), encoding: .utf8)
        #expect(pid == "42\n")
        #expect(await terminal.standardErrorText.contains("process 99"))

        try lock.release()
        #expect(FileManager.default.fileExists(atPath: lockURL.path) == false)
    }

    @Test func activeLockTimesOutWithoutRemovingTheOwner() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let lockURL = root.appending(path: "simulator.lock", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: lockURL, withIntermediateDirectories: true)
        try Data("99\n".utf8).write(to: lockURL.appending(path: "pid"))
        let clock = ImmediateClock()
        var lock = DirectoryLock(
            directory: lockURL,
            processID: 42,
            fileSystem: FoundationFileSystem(),
            clock: clock,
            processInspector: StubProcessInspector(runningProcessIDs: [99]),
            warning: { _ in },
        )

        do {
            try await lock.acquire()
            Issue.record("expected a timeout")
        } catch let failure as DirectoryLockFailure {
            #expect(failure == .timedOut(lockURL, owner: 99))
        }

        #expect(await clock.sleeps.count == 120)
        #expect(FileManager.default.fileExists(atPath: lockURL.path))
    }

    @Test func writesTheOwnerAtomically() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let lockURL = root.appending(path: "simulator.lock", directoryHint: .isDirectory)
        var lock = DirectoryLock(
            directory: lockURL,
            processID: 42,
            fileSystem: AtomicWriteEnforcingFileSystem(),
            clock: ImmediateClock(),
            processInspector: StubProcessInspector(runningProcessIDs: []),
            warning: { _ in },
        )

        try await lock.acquire()

        let pid = try String(contentsOf: lockURL.appending(path: "pid"), encoding: .utf8)
        #expect(pid == "42\n")
        try lock.release()
    }
}

private struct AtomicWriteEnforcingFileSystem: FileSystem {
    private let base = FoundationFileSystem()

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
        try base.moveItem(at: source, to: destination)
    }

    func removeItem(at url: URL) throws {
        try base.removeItem(at: url)
    }

    func read(_ url: URL) throws -> Data {
        try base.read(url)
    }

    func write(_ data: Data, to url: URL, atomically: Bool) throws {
        guard atomically else { throw NonAtomicWriteFailure() }
        try base.write(data, to: url, atomically: true)
    }

    func setPosixPermissions(_ permissions: Int, at url: URL) throws {
        try base.setPosixPermissions(permissions, at: url)
    }
}

private struct NonAtomicWriteFailure: Error {}
