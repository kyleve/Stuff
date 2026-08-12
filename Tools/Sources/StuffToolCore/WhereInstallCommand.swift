import ArgumentParser
import Foundation

public struct WhereInstallCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "./Where/install",
        abstract: "Build, sign, install, and optionally launch Where on an iPhone.",
        discussion: """
        Uses xcodebuild and Apple's devicectl without opening Xcode. Debug builds
        are optimized by default while retaining DEBUG-only developer surfaces.
        """,
    )

    @Option(help: "Exact device name, UDID, or identifier.")
    var device: String?

    @Option(help: "Xcode build configuration.")
    var configuration = "Debug"

    @Flag(
        name: .customLong("optimize"),
        inversion: .prefixedNo,
        exclusivity: .chooseLast,
        help: "Force compiler optimizations.",
    )
    var optimize = true

    @Flag(help: "Compile Debug against CloudKit instead of the local-only store.")
    var cloudkit = false

    @Flag(name: .customLong("no-launch"), help: "Install without launching the app.")
    var noLaunch = false

    @Flag(name: [.customShort("y"), .long], help: "Skip the device-unlock prompt.")
    var yes = false

    @Flag(help: "Describe the build and install without running commands.")
    var dryRun = false

    public init() {}

    public func makeRequest() throws -> WhereInstallRequest {
        guard configuration.isEmpty == false else {
            throw WhereInstallFailure.message("--configuration requires a value")
        }
        guard configuration != ".", configuration != "..",
              configuration.contains("/") == false
        else {
            throw WhereInstallFailure.message("--configuration must be a build configuration name")
        }
        if let device, device.isEmpty {
            throw WhereInstallFailure.message("--device requires a value")
        }
        return WhereInstallRequest(
            device: device,
            configuration: configuration,
            optimize: optimize,
            cloudKit: cloudkit,
            launch: noLaunch == false,
            assumeYes: yes,
            dryRun: dryRun,
        )
    }

    public mutating func run() async throws {
        let terminal = StandardTerminal()
        let environment = ProcessInfo.processInfo.environment
        let repository = environment["STUFF_REPOSITORY_ROOT"]
            .map { URL(filePath: $0, directoryHint: .isDirectory) }
            ?? URL(
                filePath: FileManager.default.currentDirectoryPath,
                directoryHint: .isDirectory,
            )
        let directories = ToolDirectories(
            environment: environment,
            homeFallback: FileManager.default.homeDirectoryForCurrentUser,
            temporaryFallback: FileManager.default.temporaryDirectory,
        )
        let service = WhereInstallService(
            runner: CommandRunner(),
            fileSystem: FoundationFileSystem(),
            terminal: terminal,
            repository: repository,
            home: directories.home,
            environment: environment,
        )
        do {
            let status = try await service.run(makeRequest())
            if status != 0 { throw ExitCode(status) }
        } catch let failure as WhereInstallFailure {
            switch failure {
                case let .message(message):
                    try await terminal.write("error: \(message)\n", to: .standardError)
                    throw ExitCode.failure
                case let .exitCode(code):
                    throw ExitCode(code)
            }
        } catch let failure as DeviceSelectionFailure {
            try await terminal.write("error: \(failure)\n", to: .standardError)
            throw ExitCode.failure
        } catch let exitCode as ExitCode {
            throw exitCode
        } catch {
            try await terminal.write("error: \(error)\n", to: .standardError)
            throw ExitCode((error as? CommandLaunchFailure)?.exitStatus ?? 1)
        }
    }
}
