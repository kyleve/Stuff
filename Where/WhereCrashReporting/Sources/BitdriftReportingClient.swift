import Capture
import Foundation

/// Bitdrift's launch-only channel choices, kept independent from app preferences.
public struct BitdriftLaunchConfiguration: Equatable, Sendable {
    public let enablesFatalIssueReporting: Bool
    public let enablesSessionReplay: Bool

    public init(enablesFatalIssueReporting: Bool, enablesSessionReplay: Bool) {
        self.enablesFatalIssueReporting = enablesFatalIssueReporting
        self.enablesSessionReplay = enablesSessionReplay
    }
}

public enum BitdriftLogLevel: Equatable, Sendable {
    case error
    case warning
    case info
    case debug
}

public enum BitdriftLogValue: Equatable, Sendable {
    case string(String)
    case integer(Int)
    case double(Double)
    case boolean(Bool)
}

public struct BitdriftLogEntry: Equatable, Sendable {
    public let level: BitdriftLogLevel
    public let message: String
    public let fields: [String: BitdriftLogValue]
    public let file: String?
    public let function: String?

    public init(
        level: BitdriftLogLevel,
        message: String,
        fields: [String: BitdriftLogValue],
        file: String?,
        function: String?,
    ) {
        self.level = level
        self.message = message
        self.fields = fields
        self.file = file
        self.function = function
    }
}

public protocol BitdriftLogWriting: Sendable {
    func write(_ entry: BitdriftLogEntry) async
}

/// A Sendable, stateless handle to Bitdrift's process logger.
public struct BitdriftLogWriter: BitdriftLogWriting {
    public init() {}

    public func write(_ entry: BitdriftLogEntry) async {
        Logger.log(
            level: entry.level.captureLevel,
            message: entry.message,
            file: entry.file,
            line: nil,
            function: entry.function,
            fields: entry.fields.captureFields,
        )
    }
}

/// Process-owned access to the Bitdrift SDK. Periscope integration stays in
/// app composition so the vendor adapter never owns the application's logger.
@MainActor
public final class BitdriftReportingClient {
    public typealias StartupFailureHandler = @MainActor (String) -> Void

    private let apiKey: String
    private let environment: [String: String]
    private var startupFailure: StartupFailureHandler
    public let writer: any BitdriftLogWriting
    public private(set) var hasStarted = false

    public init(
        apiKey: String,
        environment: [String: String],
        writer: any BitdriftLogWriting,
        startupFailure: @escaping StartupFailureHandler,
    ) {
        self.apiKey = apiKey
        self.environment = environment
        self.writer = writer
        self.startupFailure = startupFailure
    }

    public func setStartupFailureHandler(_ handler: @escaping StartupFailureHandler) {
        startupFailure = handler
    }

    public func start(configuration: BitdriftLaunchConfiguration) {
        guard !hasStarted, CrashReportingProcess.shouldStart(environment: environment) else {
            return
        }
        hasStarted = true
        Logger.start(
            withAPIKey: apiKey,
            sessionStrategy: .fixed(),
            configuration: Capture.Configuration(
                sessionReplayConfiguration: configuration.enablesSessionReplay ? .init() : nil,
                sleepMode: .disabled,
                enableFatalIssueReporting: configuration.enablesFatalIssueReporting,
            ),
            startResult: { [weak self] result in
                guard case let .failure(error) = result else { return }
                let description = String(describing: error)
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    hasStarted = false
                    startupFailure(description)
                }
            },
        )
    }

    public func setSleeping(_ isSleeping: Bool) {
        guard hasStarted else { return }
        Logger.setSleepMode(isSleeping ? .enabled : .disabled)
    }
}

extension BitdriftLogLevel {
    fileprivate var captureLevel: Capture.LogLevel {
        switch self {
            case .error: .error
            case .warning: .warning
            case .info: .info
            case .debug: .debug
        }
    }
}

extension [String: BitdriftLogValue] {
    fileprivate var captureFields: Capture.Fields {
        reduce(into: Capture.Fields()) { fields, entry in
            switch entry.value {
                case let .string(value): fields[entry.key] = value
                case let .integer(value): fields[entry.key] = value
                case let .double(value): fields[entry.key] = value
                case let .boolean(value): fields[entry.key] = value
            }
        }
    }
}
