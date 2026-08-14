import Testing
import WhereCore
@testable import WhereUI

struct PrivacyPassportPresentationTests {
    @Test func allOffDisclosesThatNothingIsShared() {
        let presentation =
            PrivacyPassportPresentation(configuration: DiagnosticReportingConfiguration(
                sharesCrashReports: false,
                sharesSessionReplays: false,
                remoteLogging: .off,
            ))

        #expect(presentation.detail.hasPrefix(String(localized: .settingsPrivacyLocation)))
        #expect(presentation.detail.contains(String(localized: .settingsPrivacyNoDiagnostics)))
    }

    @Test(arguments: RemoteLogLevel.allCases)
    func everyRemoteThresholdHasHonestCopy(level: RemoteLogLevel) {
        let presentation =
            PrivacyPassportPresentation(configuration: DiagnosticReportingConfiguration(
                sharesCrashReports: false,
                sharesSessionReplays: false,
                remoteLogging: .enabled(minimumLevel: level, metadataPolicy: .approvedFields),
            ))

        #expect(presentation.detail.contains("Diagnostic logs") || presentation.detail
            .contains("diagnostic logs"))
        #expect(presentation.detail
            .contains(String(localized: .settingsPrivacyNoDiagnostics)) == false)
    }

    @Test func activeCrashAndReplayChannelsAreBothDisclosed() {
        let presentation =
            PrivacyPassportPresentation(configuration: DiagnosticReportingConfiguration(
                sharesCrashReports: true,
                sharesSessionReplays: true,
                remoteLogging: .off,
            ))

        #expect(presentation.detail.contains(String(localized: .settingsPrivacyCrashReports)))
        #expect(presentation.detail.contains(String(localized: .settingsPrivacySessionReplay)))
    }

    #if DEBUG
        @Test func fullMetadataAddsThePersonalDataWarning() {
            let presentation =
                PrivacyPassportPresentation(configuration: DiagnosticReportingConfiguration(
                    sharesCrashReports: false,
                    sharesSessionReplays: false,
                    remoteLogging: .enabled(
                        minimumLevel: .debug,
                        metadataPolicy: .allMetadataExcludingAttachmentData,
                    ),
                ))

            #expect(presentation.detail.contains(String(localized: .settingsPrivacyFullMetadata)))
        }
    #endif
}
