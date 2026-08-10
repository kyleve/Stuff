import Testing
@testable import WhereCrashReporting

@MainActor
struct WhereCrashReportingTests {
    @Test func preservesTheSentryBootstrapConfiguration() {
        let configuration = WhereCrashReporting.configuration(
            dsn: "https://public@example.invalid/1",
            debug: true,
        )

        #expect(configuration.dsn == "https://public@example.invalid/1")
        #expect(configuration.debug)
    }

    @Test func skipsXCTestProcesses() {
        #expect(WhereCrashReporting.shouldStart(environment: [
            "XCTestConfigurationFilePath": "/tmp/tests.xctestconfiguration",
        ]) == false)
    }

    @Test func startsOrdinaryApplicationProcesses() {
        #expect(WhereCrashReporting.shouldStart(environment: [:]))
    }
}
