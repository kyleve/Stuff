import SFSafeSymbols
import SwiftUI
import WhereCore

extension PrivacyPassportPresentation.Disclosure {
    var systemSymbol: SFSymbol {
        switch self {
            case .noDiagnostics: .checkmarkShieldFill
            case .crashReports: .waveformPathEcgRectangle
            case .sessionReplay: .playRectangleOnRectangle
            case .diagnosticLogs: .ladybug
            #if DEBUG
                case .fullMetadata: .exclamationmarkTriangleFill
            #endif
        }
    }

    var title: LocalizedStringResource {
        switch self {
            case .noDiagnostics: .settingsPrivacyNoDiagnosticsTitle
            case .crashReports: .settingsPrivacyCrashReportsTitle
            case .sessionReplay: .settingsPrivacySessionReplayTitle
            case .diagnosticLogs: .settingsPrivacyLogsTitle
            #if DEBUG
                case .fullMetadata: .settingsPrivacyFullMetadataTitle
            #endif
        }
    }

    var status: LocalizedStringResource {
        switch self {
            case .noDiagnostics: .settingsPrivacyStatusNotShared
            case .crashReports, .sessionReplay, .diagnosticLogs: .settingsPrivacyStatusShared
            #if DEBUG
                case .fullMetadata: .settingsPrivacyStatusWarning
            #endif
        }
    }

    var detail: LocalizedStringResource {
        switch self {
            case .noDiagnostics: .settingsPrivacyNoDiagnostics
            case .crashReports: .settingsPrivacyCrashReports
            case .sessionReplay: .settingsPrivacySessionReplay
            case let .diagnosticLogs(level): level.privacyDetail
            #if DEBUG
                case .fullMetadata: .settingsPrivacyFullMetadata
            #endif
        }
    }
}

extension RemoteLogLevel {
    fileprivate var privacyDetail: LocalizedStringResource {
        switch self {
            case .fault: .settingsPrivacyLogsFault
            case .error: .settingsPrivacyLogsError
            case .warning: .settingsPrivacyLogsWarning
            case .notice: .settingsPrivacyLogsNotice
            case .info: .settingsPrivacyLogsInfo
            case .debug: .settingsPrivacyLogsDebug
        }
    }
}
