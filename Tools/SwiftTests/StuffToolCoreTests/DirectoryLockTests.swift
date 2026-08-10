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
}
