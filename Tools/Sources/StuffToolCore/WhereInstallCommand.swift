import ArgumentParser

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
            throw ToolFailure.message("--configuration requires a value")
        }
        guard configuration != ".", configuration != "..",
              configuration.contains("/") == false
        else {
            throw ToolFailure.message("--configuration must be a build configuration name")
        }
        if let device, device.isEmpty {
            throw ToolFailure.message("--device requires a value")
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
        let runtime = ToolRuntime()
        let status = try await performPublicCommand(terminal: runtime.terminal) {
            try await runtime.whereInstallService().run(makeRequest())
        }
        if status != 0 { throw ExitCode(status) }
    }
}
