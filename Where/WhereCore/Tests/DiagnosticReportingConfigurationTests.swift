import Foundation
import PeriscopeCore
import Testing
@testable import WhereCore

struct DiagnosticReportingConfigurationTests {
    @Test func independentExportControlsRoundTrip() throws {
        let configuration = RemoteLoggingConfiguration.enabled(
            minimumLevel: .notice,
            exportPolicy: .init(mode: .diagnostic, enabledControls: [
                .location,
                LogExportControl("example.custom"),
            ]),
        )
        #expect(try JSONDecoder().decode(
            RemoteLoggingConfiguration.self,
            from: JSONEncoder().encode(configuration),
        ) == configuration)
    }

    @Test func oldFullMetadataPreferenceGrantsOnlyTheNamedBuiltInControls() throws {
        let data = Data(
            #"{"enabled":{"minimum_level":"warning","metadata_policy":"allMetadataExcludingAttachmentData"}}"#
                .utf8,
        )
        let configuration = try JSONDecoder().decode(RemoteLoggingConfiguration.self, from: data)
        #expect(configuration.exportPolicy.mode == .diagnostic)
        #expect(configuration.exportPolicy.enabledControls == RemoteLoggingConfiguration
            .personalDataControls)
        #expect(configuration.exportPolicy[LogExportControl("example.custom")] == false)
    }

    @Test(arguments: [
        RemoteLoggingConfiguration.off,
        .enabled(minimumLevel: .notice, exportPolicy: .init(mode: .baseline, enabledControls: [])),
        .enabled(
            minimumLevel: .debug,
            exportPolicy: .init(
                mode: .diagnostic,
                enabledControls: RemoteLoggingConfiguration.personalDataControls,
            ),
        ),
    ])
    func persistedConfigurationRoundTrips(_ remoteLogging: RemoteLoggingConfiguration) throws {
        let configuration = DiagnosticReportingConfiguration(
            sharesCrashReports: false,
            sharesSessionReplays: true,
            remoteLogging: remoteLogging,
        )

        let data = try JSONEncoder().encode(configuration)

        #expect(
            try JSONDecoder().decode(DiagnosticReportingConfiguration.self, from: data)
                == configuration,
        )
    }

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
            exportPolicy: .init(mode: .baseline, enabledControls: []),
        ))
    }

    @Test func releaseNeverHonorsFullMetadata() {
        let saved = DiagnosticReportingConfiguration(
            sharesCrashReports: false,
            sharesSessionReplays: true,
            remoteLogging: .enabled(
                minimumLevel: .debug,
                exportPolicy: .init(
                    mode: .diagnostic,
                    enabledControls: RemoteLoggingConfiguration.personalDataControls,
                ),
            ),
        )

        #expect(saved.effective(isDebugBuild: false) == DiagnosticReportingConfiguration(
            sharesCrashReports: false,
            sharesSessionReplays: true,
            remoteLogging: .enabled(
                minimumLevel: .debug,
                exportPolicy: .init(mode: .baseline, enabledControls: []),
            ),
        ))
        #expect(saved.effective(isDebugBuild: true) == saved)
    }

    @Test func offCannotCarryAFullMetadataPolicy() {
        #expect(RemoteLoggingConfiguration.off.minimumLevel == nil)
        #expect(RemoteLoggingConfiguration.off.exportPolicy == LogExportPolicy(
            mode: .baseline,
            enabledControls: [],
        ))
    }
}
