import Foundation
import StuffToolCore
import Subprocess
import Testing

actor FakeCommandRunner: CommandRunning {
    private var responses: [CommandResult]
    private(set) var invocations: [CommandInvocation] = []
    private let onRun: (@Sendable (Int, CommandInvocation) async throws -> Void)?

    init(
        responses: [CommandResult],
        onRun: (@Sendable (Int, CommandInvocation) async throws -> Void)? = nil,
    ) {
        self.responses = responses
        self.onRun = onRun
    }

    func run(
        _ invocation: CommandInvocation,
        outputHandler: CommandOutputHandler?,
    ) async throws -> CommandResult {
        invocations.append(invocation)
        try await onRun?(invocations.count - 1, invocation)
        guard responses.isEmpty == false else {
            throw FakeCommandFailure.missingResponse(invocation)
        }
        let response = responses.removeFirst()
        if let outputHandler {
            if response.standardOutput.isEmpty == false {
                try await outputHandler(.standardOutput, response.standardOutput)
            }
            if response.standardError.isEmpty == false {
                try await outputHandler(.standardError, response.standardError)
            }
        }
        return response
    }
}

enum FakeCommandFailure: Error {
    case missingResponse(CommandInvocation)
}

struct InjectedMoveFailure: Error {}

final class MoveFaultFileSystem: FileSystem, @unchecked Sendable {
    private let base: FoundationFileSystem
    private let failingMoves: Set<Int>
    private let lock = NSLock()
    private var moveCount = 0

    init(base: FoundationFileSystem, failingMove: Int) {
        self.base = base
        failingMoves = [failingMove]
    }

    init(base: FoundationFileSystem, failingMoves: Set<Int>) {
        self.base = base
        self.failingMoves = failingMoves
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
        lock.lock()
        moveCount += 1
        let shouldFail = failingMoves.contains(moveCount)
        lock.unlock()
        if shouldFail { throw InjectedMoveFailure() }
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

extension CommandResult {
    static func stub(
        exitCode: Int32 = 0,
        standardOutput: String = "",
        standardError: String = "",
    ) -> CommandResult {
        CommandResult(
            terminationStatus: .exited(exitCode),
            standardOutput: Array(standardOutput.utf8),
            standardError: Array(standardError.utf8),
        )
    }
}

actor MemoryTerminal: Terminal {
    private(set) var standardOutput: [UInt8] = []
    private(set) var standardError: [UInt8] = []

    func write(_ bytes: [UInt8], to stream: TerminalStream) {
        switch stream {
            case .standardOutput:
                standardOutput.append(contentsOf: bytes)
            case .standardError:
                standardError.append(contentsOf: bytes)
        }
    }

    func isInteractive() -> Bool {
        false
    }

    var standardOutputText: String {
        String(decoding: standardOutput, as: UTF8.self)
    }

    var standardErrorText: String {
        String(decoding: standardError, as: UTF8.self)
    }
}

actor ImmediateClock: ToolClock {
    private(set) var sleeps: [Duration] = []
    private var time: TimeInterval = 0
    private let currentDate: Date

    init(currentDate: Date = Date(timeIntervalSince1970: 0)) {
        self.currentDate = currentDate
    }

    func sleep(for duration: Duration) {
        sleeps.append(duration)
        let components = duration.components
        time += Double(components.seconds) + Double(components.attoseconds) / 1e18
    }

    func now() -> TimeInterval {
        time
    }

    func date() -> Date {
        currentDate
    }
}

struct StubProcessInspector: ProcessInspecting {
    let runningProcessIDs: Set<Int32>

    func isRunning(processID: Int32) -> Bool {
        runningProcessIDs.contains(processID)
    }
}

func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "StuffToolTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

func removeTemporaryDirectory(_ directory: URL) {
    try? FileManager.default.removeItem(at: directory)
}

func fixtureData(_ name: String, extension fileExtension: String) throws -> Data {
    let url = try #require(
        Bundle.module.url(
            forResource: name,
            withExtension: fileExtension,
            subdirectory: "Fixtures",
        ),
    )
    return try Data(contentsOf: url)
}

func pngFixtureData(width: UInt32 = 1024, height: UInt32 = 1024) -> Data {
    var bytes: [UInt8] = [
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
        0,
        0,
        0,
        13,
        0x49,
        0x48,
        0x44,
        0x52,
    ]
    for value in [width, height] {
        bytes += [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF),
        ]
    }
    return Data(bytes)
}
