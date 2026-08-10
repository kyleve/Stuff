import Foundation
import StuffToolCore
import Testing

struct LedgerInstallServiceTests {
    @Test func stagesStopsExactInstalledProcessReplacesAndOpens() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let base = FoundationFileSystem()
        let applications = root.appending(path: "Applications", directoryHint: .isDirectory)
        let temporary = root.appending(path: "tmp", directoryHint: .isDirectory)
        try base.createDirectory(at: applications, withIntermediateDirectories: true)
        try base.createDirectory(at: temporary, withIntermediateDirectories: true)
        let destination = applications.appending(path: "Ledger.app", directoryHint: .isDirectory)
        try makeLedgerApp(destination, marker: "old", fileSystem: base)
        let buildRoot = temporary.appending(
            path: "Ledger-install-build-probe",
            directoryHint: .isDirectory,
        )
        let built = buildRoot.appending(
            path: "Build/Products/Release/Ledger.app",
            directoryHint: .isDirectory,
        )
        let process = "  4242 \(destination.path)/Contents/MacOS/Ledger\n"
        let runner = FakeCommandRunner(
            responses: [
                .stub(),
                .stub(standardOutput: "build output\n"),
                .stub(standardOutput: process),
                .stub(),
                .stub(),
                .stub(),
            ],
            onRun: { index, _ in
                if index == 1 {
                    try makeLedgerApp(built, marker: "new", fileSystem: base)
                }
            },
        )
        let terminal = MemoryTerminal()
        let service = makeService(
            runner: runner,
            fileSystem: base,
            terminal: terminal,
            root: root,
            applications: applications,
            temporary: temporary,
        )

        let status = try await service.run(LedgerInstallRequest())

        #expect(status == 0)
        #expect(try base.read(destination.appending(path: "Contents/marker")) == Data("new".utf8))
        #expect(base.kind(of: buildRoot) == .missing)
        #expect(base.kind(of: applications.appending(path: ".Ledger-install-probe")) == .missing)
        let invocations = await runner.invocations
        #expect(invocations.count == 6)
        #expect(invocations[0].arguments == ["exec", "--", "tuist", "generate", "--no-open"])
        #expect(invocations[1].arguments.contains("generic/platform=macOS"))
        #expect(invocations[1].arguments.contains("CODE_SIGN_IDENTITY=-"))
        #expect(invocations[2].arguments == ["-ww", "-axo", "pid=,comm="])
        #expect(invocations[3].arguments == ["-TERM", "4242"])
        #expect(invocations[5].executable == "open")
        #expect(invocations[5].arguments == [destination.path])
        #expect(await terminal.standardOutputText
            .contains("Stopped installed Ledger process(es): 4242"))
        #expect(await terminal.standardOutputText.contains("Launched. Look for the $ amount"))
    }

    @Test func dryRunDoesNotInspectTheDestinationOrRunCommands() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let runner = FakeCommandRunner(responses: [])
        let terminal = MemoryTerminal()
        let applications = root.appending(path: "missing-applications")
        let temporary = root.appending(path: "missing-temp")
        let service = makeService(
            runner: runner,
            fileSystem: FoundationFileSystem(),
            terminal: terminal,
            root: root,
            applications: applications,
            temporary: temporary,
        )

        let status = try await service.run(
            LedgerInstallRequest(openAfterInstall: false, dryRun: true),
        )

        #expect(status == 0)
        #expect(await runner.invocations.isEmpty)
        #expect(FoundationFileSystem().kind(of: applications) == .missing)
        #expect(await terminal.standardOutputText.contains("launch disabled"))
    }

    @Test func refusesASymlinkOrMalformedInstalledDestinationBeforeBuilding() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let base = FoundationFileSystem()
        let applications = root.appending(path: "Applications", directoryHint: .isDirectory)
        let temporary = root.appending(path: "tmp", directoryHint: .isDirectory)
        try base.createDirectory(at: applications, withIntermediateDirectories: true)
        try base.createDirectory(at: temporary, withIntermediateDirectories: true)
        let destination = applications.appending(path: "Ledger.app")
        try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: temporary)
        let runner = FakeCommandRunner(responses: [])
        let service = makeService(
            runner: runner,
            fileSystem: base,
            terminal: MemoryTerminal(),
            root: root,
            applications: applications,
            temporary: temporary,
        )

        do {
            _ = try await service.run(LedgerInstallRequest())
            Issue.record("expected unsafe destination failure")
        } catch let failure as LedgerInstallFailure {
            #expect(failure.description.contains("refusing to replace"))
        }
        #expect(await runner.invocations.isEmpty)
    }

    @Test func replacementFailureRestoresThePreviouslyInstalledApp() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let base = FoundationFileSystem()
        let applications = root.appending(path: "Applications", directoryHint: .isDirectory)
        let temporary = root.appending(path: "tmp", directoryHint: .isDirectory)
        try base.createDirectory(at: applications, withIntermediateDirectories: true)
        try base.createDirectory(at: temporary, withIntermediateDirectories: true)
        let destination = applications.appending(path: "Ledger.app", directoryHint: .isDirectory)
        try makeLedgerApp(destination, marker: "old", fileSystem: base)
        let built = temporary.appending(
            path: "Ledger-install-build-probe/Build/Products/Release/Ledger.app",
            directoryHint: .isDirectory,
        )
        let runner = FakeCommandRunner(
            responses: [.stub(), .stub(), .stub()],
            onRun: { index, _ in
                if index == 1 {
                    try makeLedgerApp(built, marker: "new", fileSystem: base)
                }
            },
        )
        let faulting = LedgerFaultingFileSystem(base: base, failingMove: 2)
        let service = makeService(
            runner: runner,
            fileSystem: faulting,
            terminal: MemoryTerminal(),
            root: root,
            applications: applications,
            temporary: temporary,
        )

        do {
            _ = try await service.run(LedgerInstallRequest(openAfterInstall: false))
            Issue.record("expected injected replacement failure")
        } catch is InjectedLedgerMoveFailure {
            // Expected.
        }

        #expect(try base.read(destination.appending(path: "Contents/marker")) == Data("old".utf8))
        #expect(base.kind(of: applications.appending(path: ".Ledger-install-probe")) == .missing)
        #expect(base.kind(of: temporary.appending(path: "Ledger-install-build-probe")) == .missing)
    }

    private func makeService(
        runner: FakeCommandRunner,
        fileSystem: any FileSystem,
        terminal: any Terminal,
        root: URL,
        applications: URL,
        temporary: URL,
    ) -> LedgerInstallService {
        LedgerInstallService(
            runner: runner,
            fileSystem: fileSystem,
            clock: ImmediateClock(),
            terminal: terminal,
            repository: root,
            applicationsDirectory: applications,
            temporaryDirectory: temporary,
            identifier: { "probe" },
            terminationPolicy: ProcessTerminationPolicy(
                graceChecks: 1,
                forceChecks: 1,
                interval: .milliseconds(1),
            ),
        )
    }
}

private func makeLedgerApp(
    _ app: URL,
    marker: String,
    fileSystem: FoundationFileSystem,
) throws {
    let contents = app.appending(path: "Contents", directoryHint: .isDirectory)
    let macOS = contents.appending(path: "MacOS", directoryHint: .isDirectory)
    try fileSystem.createDirectory(at: macOS, withIntermediateDirectories: true)
    try fileSystem.write(
        Data("plist".utf8),
        to: contents.appending(path: "Info.plist"),
        atomically: false,
    )
    try fileSystem.write(
        Data("binary".utf8),
        to: macOS.appending(path: "Ledger"),
        atomically: false,
    )
    try fileSystem.write(
        Data(marker.utf8),
        to: contents.appending(path: "marker"),
        atomically: false,
    )
}

private final class LedgerFaultingFileSystem: FileSystem, @unchecked Sendable {
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
        if moveCount == failingMove { throw InjectedLedgerMoveFailure() }
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

private struct InjectedLedgerMoveFailure: Error {}
