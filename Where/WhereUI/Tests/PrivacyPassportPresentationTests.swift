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

        #expect(presentation.locationDetail == String(localized: .settingsPrivacyLocation))
        #expect(presentation.disclosures == [.noDiagnostics])
    }

    @Test(arguments: RemoteLogLevel.allCases)
    func everyRemoteThresholdProducesItsOwnDisclosure(level: RemoteLogLevel) {
        let presentation =
            PrivacyPassportPresentation(configuration: DiagnosticReportingConfiguration(
                sharesCrashReports: false,
                sharesSessionReplays: false,
                remoteLogging: .enabled(minimumLevel: level, metadataPolicy: .approvedFields),
            ))

        #expect(presentation.disclosures == [.diagnosticLogs(level)])
    }

    @Test func activeChannelsUseStableDisclosureOrder() {
        let presentation =
            PrivacyPassportPresentation(configuration: DiagnosticReportingConfiguration(
                sharesCrashReports: true,
                sharesSessionReplays: true,
                remoteLogging: .enabled(
                    minimumLevel: .notice,
                    metadataPolicy: .approvedFields,
                ),
            ))

        #expect(presentation.disclosures == [
            .crashReports,
            .sessionReplay,
            .diagnosticLogs(.notice),
        ])
    }

    @Test func disabledChannelsStayHidden() {
        let presentation =
            PrivacyPassportPresentation(configuration: DiagnosticReportingConfiguration(
                sharesCrashReports: false,
                sharesSessionReplays: true,
                remoteLogging: .off,
            ))

        #expect(presentation.disclosures == [.sessionReplay])
    }

    #if DEBUG
        @Test func fullMetadataAddsASeparateWarningAfterLogs() {
            let presentation =
                PrivacyPassportPresentation(configuration: DiagnosticReportingConfiguration(
                    sharesCrashReports: false,
                    sharesSessionReplays: false,
                    remoteLogging: .enabled(
                        minimumLevel: .debug,
                        metadataPolicy: .allMetadataExcludingAttachmentData,
                    ),
                ))

            #expect(presentation.disclosures == [
                .diagnosticLogs(.debug),
                .fullMetadata,
            ])
        }
    #endif
}
