import Foundation

public struct LedgerInstallRequest: Equatable, Sendable {
    public let openAfterInstall: Bool
    public let dryRun: Bool

    public init(openAfterInstall: Bool = true, dryRun: Bool = false) {
        self.openAfterInstall = openAfterInstall
        self.dryRun = dryRun
    }
}

/// Builds, stages, validates, and transactionally replaces `/Applications/Ledger.app`.
public struct LedgerInstallService: Sendable {
    private static let appName = "Ledger"
    private static let workspace = "Stuff.xcworkspace"

    private let runner: any CommandRunning
    private let fileSystem: any FileSystem
    private let clock: any ToolClock
    private let terminal: any Terminal
    private let repository: URL
    private let applicationsDirectory: URL
    private let temporaryDirectory: URL
    private let identifier: @Sendable () -> String
    private let terminationPolicy: ProcessTerminationPolicy

    public init(
        runner: any CommandRunning,
        fileSystem: any FileSystem,
        clock: any ToolClock,
        terminal: any Terminal,
        repository: URL,
        applicationsDirectory: URL,
        temporaryDirectory: URL,
        identifier: @escaping @Sendable () -> String,
        terminationPolicy: ProcessTerminationPolicy,
    ) {
        self.runner = runner
        self.fileSystem = fileSystem
        self.clock = clock
        self.terminal = terminal
        self.repository = repository
        self.applicationsDirectory = applicationsDirectory
        self.temporaryDirectory = temporaryDirectory
        self.identifier = identifier
        self.terminationPolicy = terminationPolicy
    }

    public func run(_ request: LedgerInstallRequest) async throws -> Int32 {
        let destination = applicationsDirectory.appending(
            path: "\(Self.appName).app",
            directoryHint: .isDirectory,
        )
        if request.dryRun {
            try await terminal.write(
                "Dry run; no project generation, build, process termination, replacement, " +
                    "or launch will occur.\n",
                to: .standardOutput,
            )
            try await terminal.write(
                "Would build an ad-hoc-signed Ledger Release and transactionally install it " +
                    "to \(destination.path)" +
                    (request.openAfterInstall ? ", then launch it.\n" : "; launch disabled.\n"),
                to: .standardOutput,
            )
            return 0
        }

        try validateDestination(destination)
        let runIdentifier = identifier()
        let buildRoot = temporaryDirectory.appending(
            path: "Ledger-install-build-\(runIdentifier)",
            directoryHint: .isDirectory,
        )
        guard fileSystem.kind(of: buildRoot) == .missing else {
            throw ToolFailure
                .message("temporary build path already exists: \(buildRoot.path)")
        }
        try fileSystem.createDirectory(at: buildRoot, withIntermediateDirectories: false)
        try fileSystem.setPosixPermissions(0o700, at: buildRoot)
        defer { try? fileSystem.removeItem(at: buildRoot) }

        try await terminal.write("==> Generating the Xcode project\n", to: .standardOutput)
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

        try await terminal.write("==> Building Ledger (Release)\n", to: .standardOutput)
        let build = try await runForwarding(
            CommandInvocation(
                executable: "mise",
                arguments: [
                    "exec",
                    "--",
                    "xcodebuild",
                    "-workspace",
                    Self.workspace,
                    "-scheme",
                    Self.appName,
                    "-configuration",
                    "Release",
                    "-destination",
                    "generic/platform=macOS",
                    "-derivedDataPath",
                    buildRoot.path,
                    "CODE_SIGN_IDENTITY=-",
                    "CODE_SIGNING_REQUIRED=NO",
                    "CODE_SIGNING_ALLOWED=YES",
                    "build",
                ],
                environment: [:],
                workingDirectory: repository,
                standardInput: [],
                output: .streamed,
            ),
        )
        guard build.succeeded else { throw ToolFailure.exitCode(build.exitCode) }

        let built = buildRoot.appending(
            path: "Build/Products/Release/Ledger.app",
            directoryHint: .isDirectory,
        )
        try validateAppBundle(built, role: "build product")

        let transactionRoot = applicationsDirectory.appending(
            path: ".Ledger-install-\(runIdentifier)",
            directoryHint: .isDirectory,
        )
        guard fileSystem.kind(of: transactionRoot) == .missing else {
            throw ToolFailure.message(
                "installation staging path already exists: \(transactionRoot.path)",
            )
        }
        try fileSystem.createDirectory(at: transactionRoot, withIntermediateDirectories: false)
        var preserveTransactionRootForRecovery = false
        defer {
            if preserveTransactionRootForRecovery == false {
                try? fileSystem.removeItem(at: transactionRoot)
            }
        }
        let stage = transactionRoot.appending(path: "stage", directoryHint: .isDirectory)
        try fileSystem.createDirectory(at: stage, withIntermediateDirectories: false)
        let stagedApp = stage.appending(path: "Ledger.app", directoryHint: .isDirectory)
        try fileSystem.copyItem(at: built, to: stagedApp)
        try validateAppBundle(stagedApp, role: "staged app")

        try await terminal.write("==> Installing to \(destination.path)\n", to: .standardOutput)
        if fileSystem.kind(of: destination) == .directory {
            let installedBinary = destination.appending(path: "Contents/MacOS/Ledger")
            let outcome = try await InstalledProcessController(
                runner: runner,
                clock: clock,
                repository: repository,
                policy: terminationPolicy,
            ).terminate(executable: installedBinary)
            if outcome.matchedProcessIDs.isEmpty == false {
                try await terminal.write(
                    "==> Stopped installed Ledger process(es): " +
                        outcome.matchedProcessIDs.map(String.init).joined(separator: ", ") + "\n",
                    to: .standardOutput,
                )
            }
            if outcome.forcedProcessIDs.isEmpty == false {
                try await terminal.write(
                    "warning: force-terminated Ledger process(es): " +
                        outcome.forcedProcessIDs.map(String.init).joined(separator: ", ") + "\n",
                    to: .standardError,
                )
            }
        }

        do {
            try FileReplacementTransaction(fileSystem: fileSystem).commit(
                [FileReplacement(target: destination, staged: stagedApp)],
                backupDirectory: transactionRoot.appending(path: "backup"),
            )
        } catch let failure as FileReplacementTransactionFailure {
            preserveTransactionRootForRecovery = true
            throw failure
        }
        try await terminal.write(
            "==> Installed Ledger to \(destination.path)\n",
            to: .standardOutput,
        )
        if request.openAfterInstall {
            let open = try await runForwarding(
                CommandInvocation(
                    executable: "open",
                    arguments: [destination.path],
                    environment: [:],
                    workingDirectory: repository,
                    standardInput: [],
                    output: .streamed,
                ),
            )
            guard open.succeeded else { throw ToolFailure.exitCode(open.exitCode) }
            try await terminal.write(
                "==> Launched. Look for the $ amount in your menu bar.\n",
                to: .standardOutput,
            )
        }
        return 0
    }

    private func validateDestination(_ destination: URL) throws {
        guard applicationsDirectory.standardizedFileURL.path.hasPrefix("/"),
              fileSystem.kind(of: applicationsDirectory) == .directory
        else {
            throw ToolFailure.message(
                "installation parent is not a directory: \(applicationsDirectory.path)",
            )
        }
        switch fileSystem.kind(of: destination) {
            case .missing:
                break
            case .directory:
                try validateAppBundle(destination, role: "installed destination")
            case .file, .symbolicLink:
                throw ToolFailure.message(
                    "refusing to replace non-app destination at \(destination.path)",
                )
        }
    }

    private func validateAppBundle(_ app: URL, role: String) throws {
        guard fileSystem.kind(of: app) == .directory,
              fileSystem.kind(of: app.appending(path: "Contents/Info.plist")) == .file,
              fileSystem.kind(of: app.appending(path: "Contents/MacOS/Ledger")) == .file
        else {
            throw ToolFailure.message(
                "\(role) is not a complete Ledger.app bundle at \(app.path)",
            )
        }
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
}
