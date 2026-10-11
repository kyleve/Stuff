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
                ? .enabled(
                    minimumLevel: .warning,
                    exportPolicy: .init(mode: .baseline, enabledControls: []),
                )
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
                exportPolicy: .init(mode: .baseline, enabledControls: []),
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

    /// The app's combined switch grants only this explicit set, never future controls.
    public static let personalDataControls: Set<LogExportControl> = [
        .identifiers,
        .location,
        .userContent,
        .personalData,
    ]

    public static let off = Self(enabledConfiguration: nil)

    public static func enabled(
        minimumLevel: RemoteLogLevel,
        exportPolicy: LogExportPolicy,
    ) -> Self {
        Self(enabledConfiguration: EnabledConfiguration(
            minimumLevel: minimumLevel,
            metadataPolicy: .approvedFields,
            exportPolicy: exportPolicy,
        ))
    }

    public var exportPolicy: LogExportPolicy {
        if let policy = enabledConfiguration?.exportPolicy { return policy }
        switch enabledConfiguration?.metadataPolicy ?? .approvedFields {
            case .approvedFields:
                return LogExportPolicy(mode: .baseline, enabledControls: [])
            case .allMetadataExcludingAttachmentData:
                return LogExportPolicy(
                    mode: .diagnostic,
                    enabledControls: Self.personalDataControls,
                )
        }
    }

    public var minimumLevel: RemoteLogLevel? {
        enabledConfiguration?.minimumLevel
    }

    private enum CodingKeys: String, CodingKey {
        case enabledConfiguration = "enabled"
    }

    private struct EnabledConfiguration: Codable, Equatable {
        let minimumLevel: RemoteLogLevel
        let metadataPolicy: LegacyRemoteLogMetadataPolicy
        /// Optional for preferences written before independent export controls existed.
        let exportPolicy: LogExportPolicy?

        private enum CodingKeys: String, CodingKey {
            case minimumLevel = "minimum_level"
            case metadataPolicy = "metadata_policy"
            case exportPolicy = "export_policy"
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

private enum LegacyRemoteLogMetadataPolicy: String, Codable {
    case approvedFields
    case allMetadataExcludingAttachmentData
}
