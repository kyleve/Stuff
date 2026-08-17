import WhereCore

/// The privacy promise derived from what this process is actually sharing.
struct PrivacyPassportPresentation: Equatable {
    let locationDetail: String
    let disclosures: [Disclosure]

    enum Disclosure: Equatable, Identifiable {
        case noDiagnostics
        case crashReports
        case sessionReplay
        case diagnosticLogs(RemoteLogLevel)
        #if DEBUG
            case fullMetadata
        #endif

        enum ID: Hashable {
            case noDiagnostics
            case crashReports
            case sessionReplay
            case diagnosticLogs
            #if DEBUG
                case fullMetadata
            #endif
        }

        var id: ID {
            switch self {
                case .noDiagnostics: .noDiagnostics
                case .crashReports: .crashReports
                case .sessionReplay: .sessionReplay
                case .diagnosticLogs: .diagnosticLogs
                #if DEBUG
                    case .fullMetadata: .fullMetadata
                #endif
            }
        }
    }

    init(configuration: DiagnosticReportingConfiguration) {
        locationDetail = String(localized: .settingsPrivacyLocation)

        var disclosures: [Disclosure] = []
        if !configuration.sharesCrashReports,
           !configuration.sharesSessionReplays,
           configuration.remoteLogging == .off
        {
            disclosures.append(.noDiagnostics)
        } else {
            if configuration.sharesCrashReports {
                disclosures.append(.crashReports)
            }
            if configuration.sharesSessionReplays {
                disclosures.append(.sessionReplay)
            }
            if let level = configuration.remoteLogging.minimumLevel {
                disclosures.append(.diagnosticLogs(level))
            }
            #if DEBUG
                if configuration.remoteLogging.metadataPolicy
                    == .allMetadataExcludingAttachmentData
                {
                    disclosures.append(.fullMetadata)
                }
            #endif
        }
        self.disclosures = disclosures
    }
}
