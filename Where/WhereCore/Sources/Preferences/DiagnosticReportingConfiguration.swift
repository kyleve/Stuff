import PeriscopeCore

/// The vendor-neutral choices controlling diagnostic data sent off-device.
/// `WherePreferences` persists this value directly. Preserve decoding of every
/// previously written shape when this type or its nested types change.
public struct DiagnosticReportingConfiguration: Codable, Equatable, Sendable {
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
        if let minimumLevel = copy.remoteLogging.minimumLevel {
            copy.remoteLogging = .enabled(
                minimumLevel: minimumLevel,
                metadataPolicy: .approvedFields,
            )
        }
        return copy
    }

    private enum CodingKeys: String, CodingKey {
        case sharesCrashReports = "shares_crash_reports"
        case sharesSessionReplays = "shares_session_replays"
        case remoteLogging = "remote_logging"
    }
}

/// A remote logging policy that is Off or contains one complete enabled configuration.
public struct RemoteLoggingConfiguration: Codable, Equatable, Sendable {
    private let enabledConfiguration: EnabledConfiguration?

    public static let off = Self(enabledConfiguration: nil)

    public static func enabled(
        minimumLevel: RemoteLogLevel,
        metadataPolicy: RemoteLogMetadataPolicy,
    ) -> Self {
        Self(enabledConfiguration: EnabledConfiguration(
            minimumLevel: minimumLevel,
            metadataPolicy: metadataPolicy,
        ))
    }

    public var minimumLevel: RemoteLogLevel? {
        enabledConfiguration?.minimumLevel
    }

    public var metadataPolicy: RemoteLogMetadataPolicy {
        enabledConfiguration?.metadataPolicy ?? .approvedFields
    }

    private enum CodingKeys: String, CodingKey {
        case enabledConfiguration = "enabled"
    }

    private struct EnabledConfiguration: Codable, Equatable {
        let minimumLevel: RemoteLogLevel
        let metadataPolicy: RemoteLogMetadataPolicy

        private enum CodingKeys: String, CodingKey {
            case minimumLevel = "minimum_level"
            case metadataPolicy = "metadata_policy"
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
