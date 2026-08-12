import ArgumentParser

/// The common recoverable failures emitted by command orchestration.
public enum ToolFailure: Error, Equatable, CustomStringConvertible, Sendable {
    case message(String)
    case exitCode(Int32)
    case reported

    public var description: String {
        switch self {
            case let .message(message): message
            case let .exitCode(code): "command exited with status \(code)"
            case .reported: "command failed"
        }
    }

    public var exitStatus: Int32 {
        switch self {
            case .message, .reported: 1
            case let .exitCode(code): code
        }
    }
}

private protocol PublicCommandFailure: Error {
    var publicMessage: String? { get }
    var publicExitStatus: Int32 { get }
}

extension ToolFailure: PublicCommandFailure {
    fileprivate var publicMessage: String? {
        guard case let .message(message) = self else { return nil }
        return message
    }

    fileprivate var publicExitStatus: Int32 {
        exitStatus
    }
}

extension CommandLaunchFailure: PublicCommandFailure {
    fileprivate var publicMessage: String? {
        description
    }

    fileprivate var publicExitStatus: Int32 {
        exitStatus
    }
}

extension DeviceSelectionFailure: PublicCommandFailure {}

extension DirectoryLockFailure: PublicCommandFailure {}

extension FileReplacementTransactionFailure: PublicCommandFailure {}

extension IconCatalogFailure: PublicCommandFailure {}

extension InstalledProcessFailure: PublicCommandFailure {
    fileprivate var publicExitStatus: Int32 {
        switch self {
            case .message: 1
            case let .exitCode(code): code
        }
    }
}

extension PublicCommandFailure where Self: CustomStringConvertible {
    fileprivate var publicMessage: String? {
        description
    }

    fileprivate var publicExitStatus: Int32 {
        1
    }
}

func performPublicCommand<Result>(
    terminal: any Terminal,
    operation: () async throws -> Result,
) async throws -> Result {
    do {
        return try await operation()
    } catch let exitCode as ExitCode {
        throw exitCode
    } catch let failure as any PublicCommandFailure {
        if let message = failure.publicMessage {
            try await terminal.write("error: \(message)\n", to: .standardError)
        }
        throw ExitCode(failure.publicExitStatus)
    } catch {
        try await terminal.write("error: \(error)\n", to: .standardError)
        throw ExitCode.failure
    }
}

public struct PublicCommandTermination: Equatable, Sendable {
    public let message: String
    public let stream: TerminalStream
    public let exitCode: Int32

    public init(
        message: String,
        stream: TerminalStream,
        exitCode: Int32,
    ) {
        self.message = message
        self.stream = stream
        self.exitCode = exitCode
    }
}

/// Maps the launcher's private selector to one public repository command.
public enum PublicCommand: String, CaseIterable, Sendable {
    case flaky
    case icons
    case ledgerInstall = "ledger-install"
    case profile
    case simulator
    case test
    case whereInstall = "where-install"
    case xcstrings

    public var publicPath: String {
        switch self {
            case .flaky: "./flaky"
            case .icons: "./icons"
            case .ledgerInstall: "./Ledger/install"
            case .profile: "./profile"
            case .simulator: "./simulator"
            case .test: "./test"
            case .whereInstall: "./Where/install"
            case .xcstrings: "./xcstrings"
        }
    }

    public var commandType: ParsableCommand.Type {
        switch self {
            case .flaky: FlakyCommand.self
            case .icons: IconsCommand.self
            case .ledgerInstall: LedgerInstallCommand.self
            case .profile: ProfileCommand.self
            case .simulator: SimulatorCommand.self
            case .test: TestCommand.self
            case .whereInstall: WhereInstallCommand.self
            case .xcstrings: XCStringsCommand.self
        }
    }

    public var usageExitCode: Int32 {
        self == .ledgerInstall ? 2 : 1
    }

    public var noArgumentTermination: PublicCommandTermination? {
        guard self == .icons else { return nil }
        return PublicCommandTermination(
            message: commandType.helpMessage(),
            stream: .standardOutput,
            exitCode: usageExitCode,
        )
    }

    public func termination(for error: any Error) -> PublicCommandTermination {
        let parserExitCode = commandType.exitCode(for: error)
        return PublicCommandTermination(
            message: commandType.fullMessage(for: error),
            stream: parserExitCode.isSuccess ? .standardOutput : .standardError,
            exitCode: parserExitCode == .validationFailure
                ? usageExitCode
                : parserExitCode.rawValue,
        )
    }
}
