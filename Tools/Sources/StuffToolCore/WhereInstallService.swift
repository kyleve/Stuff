import Foundation

public struct WhereInstallRequest: Equatable, Sendable {
    public let device: String?
    public let configuration: String
    public let optimize: Bool
    public let cloudKit: Bool
    public let launch: Bool
    public let assumeYes: Bool
    public let dryRun: Bool

    public init(
        device: String? = nil,
        configuration: String = "Debug",
        optimize: Bool = true,
        cloudKit: Bool = false,
        launch: Bool = true,
        assumeYes: Bool = false,
        dryRun: Bool = false,
    ) {
        self.device = device
        self.configuration = configuration
        self.optimize = optimize
        self.cloudKit = cloudKit
        self.launch = launch
        self.assumeYes = assumeYes
        self.dryRun = dryRun
    }
}

/// Builds and installs the signed Where app through typed `devicectl` selection.
public struct WhereInstallService: Sendable {
    private static let workspace = "Stuff.xcworkspace"
    private static let scheme = "Where"
    private static let bundleID = "com.stuff.where"

    private struct Paths {
        let work: URL
        let derived: URL
        let devicesJSON: URL

        func app(configuration: String) -> URL {
            derived.appending(
                path: "Build/Products/\(configuration)-iphoneos/Where.app",
                directoryHint: .isDirectory,
            )
        }
    }

    private let runner: any CommandRunning
    private let fileSystem: any FileSystem
    private let terminal: any Terminal
    private let repository: URL
    private let home: URL
    private let environment: [String: String]

    public init(
        runner: any CommandRunning,
        fileSystem: any FileSystem,
        terminal: any Terminal,
        repository: URL,
        home: URL,
        environment: [String: String],
    ) {
        self.runner = runner
        self.fileSystem = fileSystem
        self.terminal = terminal
        self.repository = repository
        self.home = home
        self.environment = environment
    }

    public func run(_ request: WhereInstallRequest) async throws -> Int32 {
        let paths = makePaths()
        if request.dryRun {
            try await printDryRun(request, paths: paths)
            return 0
        }

        let teamLookup = try await runner.run(
            CommandInvocation(
                executable: "mise",
                arguments: [
                    "exec",
                    "--",
                    "sh",
                    "-c",
                    #"printf "%s" "${TUIST_DEVELOPMENT_TEAM:-}""#,
                ],
                environment: [:],
                workingDirectory: repository,
                standardInput: [],
                output: .captured,
            ),
            outputHandler: { stream, bytes in
                if stream == .standardError {
                    try await terminal.write(bytes, to: .standardError)
                }
            },
        )
        guard teamLookup.succeeded else {
            throw ToolFailure.exitCode(teamLookup.exitCode)
        }
        let team = teamLookup.standardOutputText.trimmingCharacters(
            in: .whitespacesAndNewlines,
        )
        guard team.isEmpty == false else {
            throw ToolFailure.message("""
            no Apple Developer team configured — a device build can't be signed.

            Set it once (writes the gitignored .mise.local.toml), then re-run:
              ./ide --team-id <ABCDE12345>
            """)
        }

        try fileSystem.createDirectory(at: paths.work, withIntermediateDirectories: true)
        try await terminal.write("==> tuist generate --no-open\n", to: .standardOutput)
        let generation = try await runner.run(
            CommandInvocation(
                executable: "mise",
                arguments: ["exec", "--", "tuist", "generate", "--no-open"],
                environment: [:],
                workingDirectory: repository,
                standardInput: [],
                output: .streamed,
            ),
            outputHandler: { stream, bytes in
                if stream == .standardError {
                    try await terminal.write(bytes, to: .standardError)
                }
            },
        )
        guard generation.succeeded else {
            throw ToolFailure.exitCode(generation.exitCode)
        }

        let optimizationLabel = request.optimize ? ", optimized" : ""
        try await terminal.write(
            "==> xcodebuild (\(request.configuration)\(optimizationLabel)) for device\n",
            to: .standardOutput,
        )
        let build = try await runForwarding(buildInvocation(request, derived: paths.derived))
        guard build.succeeded else { throw ToolFailure.exitCode(build.exitCode) }

        let app = paths.app(configuration: request.configuration)
        guard fileSystem.kind(of: app) == .directory else {
            throw ToolFailure.message("built app not found at \(app.path)")
        }

        try await terminal.write("==> resolving device\n", to: .standardOutput)
        let list = try await runner.run(
            CommandInvocation(
                executable: "xcrun",
                arguments: [
                    "devicectl",
                    "list",
                    "devices",
                    "--json-output",
                    paths.devicesJSON.path,
                ],
                environment: [:],
                workingDirectory: repository,
                standardInput: [],
                output: .streamed,
            ),
            outputHandler: { stream, bytes in
                if stream == .standardError {
                    try await terminal.write(bytes, to: .standardError)
                }
            },
        )
        guard list.succeeded else { throw ToolFailure.exitCode(list.exitCode) }
        let devices: Data
        do {
            devices = try fileSystem.read(paths.devicesJSON)
        } catch {
            throw ToolFailure.message(
                "couldn't read devicectl's device list (\(error)). " +
                    "Run `xcrun devicectl list devices` to check your setup.",
            )
        }
        let selected = try DeviceSelector().select(from: devices, filter: request.device)
        try await terminal.write(
            "    using: \(selected.name) (\(selected.identifier))\n",
            to: .standardError,
        )

        if request.assumeYes == false, await terminal.isInputInteractive() {
            try await terminal.write(
                "Make sure \"\(selected.name)\" is unlocked and trusts this Mac.\n",
                to: .standardOutput,
            )
            guard try await terminal.readLine(
                prompt: "Press Enter to install, or Ctrl-C to cancel... ",
            ) != nil else {
                throw ToolFailure.exitCode(1)
            }
        }

        try await terminal.write("==> installing to device\n", to: .standardOutput)
        let install = try await runForwarding(
            CommandInvocation(
                executable: "xcrun",
                arguments: [
                    "devicectl",
                    "device",
                    "install",
                    "app",
                    "--device",
                    selected.identifier,
                    app.path,
                ],
                environment: [:],
                workingDirectory: repository,
                standardInput: [],
                output: .streamed,
            ),
        )
        guard install.succeeded else { throw ToolFailure.exitCode(install.exitCode) }

        if request.launch {
            let suffix = request.cloudKit ? " with CloudKit validation enabled" : ""
            try await terminal.write(
                "==> launching \(Self.bundleID)\(suffix)\n",
                to: .standardOutput,
            )
            let launch = try await runForwarding(
                CommandInvocation(
                    executable: "xcrun",
                    arguments: [
                        "devicectl",
                        "device",
                        "process",
                        "launch",
                        "--device",
                        selected.identifier,
                        "--terminate-existing",
                        Self.bundleID,
                    ],
                    environment: [:],
                    workingDirectory: repository,
                    standardInput: [],
                    output: .streamed,
                ),
            )
            guard launch.succeeded else { throw ToolFailure.exitCode(launch.exitCode) }
        }

        try await terminal.write(
            "Done. (Build products: \(paths.derived.path))\n",
            to: .standardOutput,
        )
        return 0
    }

    private func makePaths() -> Paths {
        let configured = environment["WHERE_INSTALL_WORKDIR"].flatMap { path in
            path.isEmpty ? nil : resolveUserPath(path)
        }
        let work = configured ?? home
            .appending(path: "Library/Developer/Xcode/DerivedData", directoryHint: .isDirectory)
            .appending(
                path: "where-install-\(repository.lastPathComponent)",
                directoryHint: .isDirectory,
            )
        return Paths(
            work: work,
            derived: work.appending(path: "DerivedData", directoryHint: .isDirectory),
            devicesJSON: work.appending(path: "devices.json"),
        )
    }

    private func buildInvocation(
        _ request: WhereInstallRequest,
        derived: URL,
    ) -> CommandInvocation {
        var arguments = [
            "exec",
            "--",
            "xcodebuild",
            "build",
            "-workspace",
            Self.workspace,
            "-scheme",
            Self.scheme,
            "-configuration",
            request.configuration,
            "-destination",
            "generic/platform=iOS",
            "-derivedDataPath",
            derived.path,
            "-allowProvisioningUpdates",
        ]
        if request.optimize {
            arguments += ["SWIFT_OPTIMIZATION_LEVEL=-O", "GCC_OPTIMIZATION_LEVEL=s"]
        }
        if request.cloudKit {
            arguments.append(
                "SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) WHERE_CLOUDKIT_VALIDATION",
            )
        }
        return CommandInvocation(
            executable: "mise",
            arguments: arguments,
            environment: [:],
            workingDirectory: repository,
            standardInput: [],
            output: .streamed,
        )
    }

    private func printDryRun(_ request: WhereInstallRequest, paths: Paths) async throws {
        let optimization = request.optimize ? " with forced optimizations" : ""
        let cloudKit = request.cloudKit ? " and CloudKit validation" : ""
        let target = request.device.map { "device \"\($0)\"" }
            ?? "the sole paired physical iOS device"
        try await terminal.write(
            "Dry run; no project generation, build, device query, installation, or launch " +
                "will occur.\n",
            to: .standardOutput,
        )
        try await terminal.write(
            "Would build Where (\(request.configuration)\(optimization)\(cloudKit)) for " +
                "generic iOS into \(paths.derived.path).\n",
            to: .standardOutput,
        )
        try await terminal.write(
            "Would install com.stuff.where to \(target)" +
                (request.launch ? " and launch it.\n" : "; launch disabled.\n"),
            to: .standardOutput,
        )
    }

    private func runForwarding(_ invocation: CommandInvocation) async throws -> CommandResult {
        try await runner.run(
            invocation,
            outputHandler: { stream, bytes in
                try await terminal.write(
                    bytes,
                    to: stream == .standardOutput ? .standardOutput : .standardError,
                )
            },
        )
    }

    private func resolveUserPath(_ path: String) -> URL {
        path.hasPrefix("/")
            ? URL(filePath: path)
            : URL(filePath: path, relativeTo: repository).standardizedFileURL
    }
}
