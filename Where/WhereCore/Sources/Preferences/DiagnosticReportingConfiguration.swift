import PeriscopeCore

/// The vendor-neutral choices controlling diagnostic data sent off-device.
public struct DiagnosticReportingConfiguration: Equatable, Sendable {
    public var sharesCrashReports: Bool
    public var sharesSessionReplays: Bool
    public var remoteLogging: RemoteLoggingConfiguration

    public init(
        sharesCrashReports: Bool,
        sharesSessionReplays: Bool,
        remoteLogging: RemoteLoggingConfiguration,
    ) {
        self.sharesCrashReports = sharesCrashReports
        self.sharesSessionReplays = sharesSessionReplays
        self.remoteLogging = remoteLogging
    }

    /// First-install choices for an explicitly named build flavor.
    public static func defaults(isDebugBuild: Bool) -> Self {
        Self(
            sharesCrashReports: true,
            sharesSessionReplays: false,
            remoteLogging: isDebugBuild
                ? .enabled(minimumLevel: .warning, metadataPolicy: .approvedFields)
                : .off,
        )
    }

    public static var currentBuildDefaults: Self {
        #if DEBUG
            defaults(isDebugBuild: true)
        #else
            defaults(isDebugBuild: false)
        #endif
    }

    /// The policy this build is allowed to apply. Release builds never export
    /// the expanded metadata set even if a Debug build persisted that choice.
    public func effective(isDebugBuild: Bool) -> Self {
        guard !isDebugBuild else { return self }
        var copy = self
        if case let .enabled(minimumLevel, _) = copy.remoteLogging {
            copy.remoteLogging = .enabled(
                minimumLevel: minimumLevel,
                metadataPolicy: .approvedFields,
            )
        }
        return copy
    }
}

public enum RemoteLoggingConfiguration: Equatable, Sendable {
    case off
    case enabled(minimumLevel: RemoteLogLevel, metadataPolicy: RemoteLogMetadataPolicy)

    public var minimumLevel: RemoteLogLevel? {
        switch self {
            case .off: nil
            case let .enabled(minimumLevel, _): minimumLevel
        }
    }

    public var metadataPolicy: RemoteLogMetadataPolicy {
        switch self {
            case .off: .approvedFields
            case let .enabled(_, metadataPolicy): metadataPolicy
        }
    }
}

public enum RemoteLogLevel: String, CaseIterable, Codable, Sendable {
    case fault
    case error
    case warning
    case notice
    case info
    case debug

    public var periscopeLevel: LogLevel {
        switch self {
            case .fault: .fault
            case .error: .error
            case .warning: .warning
            case .notice: .notice
            case .info: .info
            case .debug: .debug
        }
    }
}

public enum RemoteLogMetadataPolicy: String, Codable, Sendable {
    case approvedFields
    case allMetadataExcludingAttachmentData
}
