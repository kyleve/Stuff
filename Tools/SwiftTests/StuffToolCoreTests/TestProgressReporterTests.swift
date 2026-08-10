import Foundation
import StuffToolCore
import Testing

struct TestProgressReporterTests {
    @Test func parsesProgressCachesCountsAndKeepsTheRawLog() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let terminal = MemoryTerminal()
        let clock = ImmediateClock()
        let fileSystem = FoundationFileSystem()
        let counts = root.appending(path: "counts.json")
        try Data("{\"tests\":2,\"images\":1}".utf8).write(to: counts)
        let log = root.appending(path: "run.log")
        let reporter = try TestProgressReporter(
            scheme: "StuffSnapshotTests",
            heartbeat: 15,
            statusURL: root.appending(path: "status"),
            countsURL: counts,
            logURL: log,
            countImages: true,
            terminal: terminal,
            fileSystem: fileSystem,
            clock: clock,
        )
        try await reporter.start()
        let outputData = try fixtureData("xcodebuild", extension: "log")
        let output = String(decoding: outputData, as: UTF8.self)

        try await reporter.consume(.standardOutput, bytes: Array(outputData))
        let summary = try await reporter.finish()

        #expect(summary == TestProgressSummary(tests: 2, images: 1, failures: 1))
        #expect(await terminal.standardOutputText.contains("✘ ExampleSuite/second()"))
        #expect(await terminal.standardOutputText.contains("2 tests, 1 images in 0:00 — 1 failed"))
        #expect(try String(contentsOf: log, encoding: .utf8) == output)
        #expect(fileSystem.kind(of: URL(filePath: counts.path + ".empty")) == .missing)
    }

    @Test func zeroTestsIsObservableAndCreatesTheFailureMarker() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let terminal = MemoryTerminal()
        let counts = root.appending(path: "counts.json")
        let reporter = try TestProgressReporter(
            scheme: "Stuff-iOS-Tests",
            heartbeat: 15,
            statusURL: nil,
            countsURL: counts,
            logURL: root.appending(path: "run.log"),
            countImages: false,
            terminal: terminal,
            fileSystem: FoundationFileSystem(),
            clock: ImmediateClock(),
        )

        try await reporter.start()
        let summary = try await reporter.finish()

        #expect(summary.matchedTests == false)
        #expect(await terminal.standardOutputText.contains("nothing ran"))
        #expect(FileManager.default.fileExists(atPath: counts.path + ".empty"))
    }

    @Test func corruptProgressCacheFallsBackWithAnObservableWarning() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let counts = root.appending(path: "counts.json")
        try Data("not-json".utf8).write(to: counts)
        let terminal = MemoryTerminal()
        let reporter = try TestProgressReporter(
            scheme: "Stuff-iOS-Tests",
            heartbeat: 15,
            statusURL: nil,
            countsURL: counts,
            logURL: root.appending(path: "run.log"),
            countImages: false,
            terminal: terminal,
            fileSystem: FoundationFileSystem(),
            clock: ImmediateClock(),
        )

        try await reporter.start()
        _ = try await reporter.finish()

        #expect(await terminal.standardErrorText.contains(
            "warning: could not read progress counts",
        ))
    }
}
