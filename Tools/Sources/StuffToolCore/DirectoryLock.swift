import Foundation

public enum DirectoryLockFailure: Error, Equatable, CustomStringConvertible, Sendable {
    case timedOut(URL, owner: Int32?)

    public var description: String {
        switch self {
            case let .timedOut(url, owner):
                let ownerDescription = owner.map { " (pid \($0))" } ?? ""
                return "timed out waiting for the ./simulator run holding \(url.path)\(ownerDescription)."
        }
    }
}

public struct DirectoryLock: Sendable {
    public let directory: URL
    private let processID: Int32
    private let fileSystem: any FileSystem
    private let clock: any ToolClock
    private let processInspector: any ProcessInspecting
    private let warning: @Sendable (String) async throws -> Void
    private var held = false

    public init(
        directory: URL,
        processID: Int32,
        fileSystem: any FileSystem,
        clock: any ToolClock,
        processInspector: any ProcessInspecting,
        warning: @escaping @Sendable (String) async throws -> Void,
    ) {
        self.directory = directory
        self.processID = processID
        self.fileSystem = fileSystem
        self.clock = clock
        self.processInspector = processInspector
        self.warning = warning
    }

    public mutating func acquire() async throws {
        guard held == false else { return }
        var waited = 0
        var staleCleared = false
        while true {
            do {
                try fileSystem.createDirectory(at: directory, withIntermediateDirectories: false)
            } catch {
                guard fileSystem.kind(of: directory) == .directory else { throw error }
                let owner = lockOwner()
                if staleCleared == false,
                   let owner,
                   processInspector.isRunning(processID: owner) == false
                {
                    try await warning(
                        "warning: clearing the lock left behind by process \(owner)\n",
                    )
                    try fileSystem.removeItem(at: directory)
                    staleCleared = true
                    continue
                }
                guard waited < 120 else {
                    throw DirectoryLockFailure.timedOut(directory, owner: owner)
                }
                try await clock.sleep(for: .seconds(1))
                waited += 1
                continue
            }

            do {
                try fileSystem.write(
                    Data("\(processID)\n".utf8),
                    to: directory.appending(path: "pid"),
                    atomically: false,
                )
                held = true
                return
            } catch {
                try? fileSystem.removeItem(at: directory)
                throw error
            }
        }
    }

    public mutating func release() throws {
        guard held else { return }
        if fileSystem.kind(of: directory) != .missing {
            try fileSystem.removeItem(at: directory)
        }
        held = false
    }

    private func lockOwner() -> Int32? {
        let pidURL = directory.appending(path: "pid")
        guard let text = try? String(decoding: fileSystem.read(pidURL), as: UTF8.self) else {
            return nil
        }
        return Int32(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
