import Darwin
import Foundation

/// Constructs production command services from one captured process environment.
struct ToolRuntime {
    let terminal = StandardTerminal()

    private let clock = ContinuousToolClock()
    private let directories: ToolDirectories
    private let environment: [String: String]
    private let fileSystem = FoundationFileSystem()
    private let processID: Int32
    private let repository: URL
    private let runner = CommandRunner()

    init() {
        let environment = ProcessInfo.processInfo.environment
        self.environment = environment
        repository = environment["STUFF_REPOSITORY_ROOT"]
            .map { URL(filePath: $0, directoryHint: .isDirectory) }
            ?? URL(
                filePath: FileManager.default.currentDirectoryPath,
                directoryHint: .isDirectory,
            )
        directories = ToolDirectories(
            environment: environment,
            homeFallback: FileManager.default.homeDirectoryForCurrentUser,
            temporaryFallback: FileManager.default.temporaryDirectory,
        )
        processID = getpid()
    }

    func testService() -> TestService {
        TestService(
            runner: runner,
            simulator: makeSimulator(
                terminal: StandardErrorOnlyTerminal(base: terminal),
            ),
            fileSystem: fileSystem,
            clock: clock,
            terminal: terminal,
            repository: repository,
            temporaryDirectory: directories.temporary,
            environment: environment,
        )
    }

    func profileService() -> ProfileService {
        ProfileService(
            runner: runner,
            simulator: makeSimulator(terminal: StandardErrorOnlyTerminal(base: terminal)),
            fileSystem: fileSystem,
            clock: clock,
            terminal: terminal,
            repository: repository,
            temporaryDirectory: directories.temporary,
            environment: environment,
        )
    }

    func flakyService() -> FlakyService {
        FlakyService(
            runner: runner,
            simulator: makeSimulator(terminal: StandardErrorOnlyTerminal(base: terminal)),
            fileSystem: fileSystem,
            clock: clock,
            terminal: terminal,
            repository: repository,
            home: directories.home,
            environment: environment,
        )
    }

    func simulatorService() -> SimulatorService {
        makeSimulator(terminal: terminal)
    }

    func iconsService() -> IconsService {
        IconsService(
            fileSystem: fileSystem,
            terminal: terminal,
            repository: repository,
            transactionIdentifier: { UUID().uuidString },
        )
    }

    func whereInstallService() -> WhereInstallService {
        WhereInstallService(
            runner: runner,
            fileSystem: fileSystem,
            terminal: terminal,
            repository: repository,
            home: directories.home,
            environment: environment,
        )
    }

    func ledgerInstallService() -> LedgerInstallService {
        LedgerInstallService(
            runner: runner,
            fileSystem: fileSystem,
            clock: clock,
            terminal: terminal,
            repository: repository,
            applicationsDirectory: URL(
                filePath: "/Applications",
                directoryHint: .isDirectory,
            ),
            temporaryDirectory: directories.temporary,
            identifier: { UUID().uuidString },
            terminationPolicy: ProcessTerminationPolicy(
                graceChecks: 50,
                forceChecks: 10,
                interval: .milliseconds(100),
            ),
        )
    }

    private func makeSimulator(terminal: any Terminal) -> SimulatorService {
        SimulatorService(
            runner: runner,
            fileSystem: fileSystem,
            clock: clock,
            processInspector: SystemProcessInspector(),
            terminal: terminal,
            repository: repository,
            home: directories.home,
            temporaryDirectory: directories.temporary,
            processID: processID,
        )
    }
}
