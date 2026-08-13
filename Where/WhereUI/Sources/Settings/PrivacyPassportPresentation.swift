import WhereCore

/// The privacy promise derived from what this process is actually sharing.
struct PrivacyPassportPresentation: Equatable {
    let detail: String

    init(configuration: DiagnosticReportingConfiguration) {
        var sentences = [String(localized: .settingsPrivacyLocation)]
        if !configuration.sharesCrashReports,
           !configuration.sharesSessionReplays,
           configuration.remoteLogging == .off
        {
            sentences.append(String(localized: .settingsPrivacyNoDiagnostics))
        } else {
            if configuration.sharesCrashReports {
                sentences.append(String(localized: .settingsPrivacyCrashReports))
            }
            if configuration.sharesSessionReplays {
                sentences.append(String(localized: .settingsPrivacySessionReplay))
            }
            if let level = configuration.remoteLogging.minimumLevel {
                sentences.append(level.privacySentence)
            }
            #if DEBUG
                if configuration.remoteLogging.metadataPolicy
                    == .allMetadataExcludingAttachmentData
                {
                    sentences.append(String(localized: .settingsPrivacyFullMetadata))
                }
            #endif
        }
        detail = sentences.joined(separator: " ")
    }
}

extension RemoteLogLevel {
    fileprivate var privacySentence: String {
        switch self {
            case .fault: String(localized: .settingsPrivacyLogsFault)
            case .error: String(localized: .settingsPrivacyLogsError)
            case .warning: String(localized: .settingsPrivacyLogsWarning)
            case .notice: String(localized: .settingsPrivacyLogsNotice)
            case .info: String(localized: .settingsPrivacyLogsInfo)
            case .debug: String(localized: .settingsPrivacyLogsDebug)
        }
    }
}
