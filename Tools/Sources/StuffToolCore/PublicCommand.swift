import ArgumentParser

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
