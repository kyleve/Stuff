import Foundation
import StuffToolCore
import Subprocess
import Testing

actor FakeCommandRunner: CommandRunning {
    private var responses: [CommandResult]
    private(set) var invocations: [CommandInvocation] = []

    init(responses: [CommandResult]) {
        self.responses = responses
    }

    func run(
        _ invocation: CommandInvocation,
        outputHandler: CommandOutputHandler?,
    ) async throws -> CommandResult {
        invocations.append(invocation)
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

    func sleep(for duration: Duration) {
        sleeps.append(duration)
        let components = duration.components
        time += Double(components.seconds) + Double(components.attoseconds) / 1e18
    }

    func now() -> TimeInterval {
        time
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
