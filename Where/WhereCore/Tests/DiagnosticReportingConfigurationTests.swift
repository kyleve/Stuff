import Testing
@testable import WhereCore

struct DiagnosticReportingConfigurationTests {
    @Test func releaseDefaultsToCrashOnly() {
        let configuration = DiagnosticReportingConfiguration.defaults(isDebugBuild: false)

        #expect(configuration.sharesCrashReports)
        #expect(configuration.sharesSessionReplays == false)
        #expect(configuration.remoteLogging == .off)
    }

    @Test func debugDefaultsToWarningLogs() {
        let configuration = DiagnosticReportingConfiguration.defaults(isDebugBuild: true)

        #expect(configuration.sharesCrashReports)
        #expect(configuration.sharesSessionReplays == false)
        #expect(configuration.remoteLogging == .enabled(
            minimumLevel: .warning,
            metadataPolicy: .approvedFields,
        ))
    }

    @Test func releaseNeverHonorsFullMetadata() {
        let saved = DiagnosticReportingConfiguration(
            sharesCrashReports: false,
            sharesSessionReplays: true,
            remoteLogging: .enabled(
                minimumLevel: .debug,
                metadataPolicy: .allMetadataExcludingAttachmentData,
            ),
        )

        #expect(saved.effective(isDebugBuild: false) == DiagnosticReportingConfiguration(
            sharesCrashReports: false,
            sharesSessionReplays: true,
            remoteLogging: .enabled(
                minimumLevel: .debug,
                metadataPolicy: .approvedFields,
            ),
        ))
        #expect(saved.effective(isDebugBuild: true) == saved)
    }

    @Test func offCannotCarryAFullMetadataPolicy() {
        #expect(RemoteLoggingConfiguration.off.minimumLevel == nil)
        #expect(RemoteLoggingConfiguration.off.metadataPolicy == .approvedFields)
    }
}
