import Testing
@testable import WhereCrashReporting

@MainActor
struct SentryCrashReporterTests {
    @Test func preservesBootstrapConfiguration() {
        let reporter = SentryCrashReporter(
            dsn: "https://public@example.invalid/1",
            debug: true,
        )

        #expect(reporter.configuration.dsn == "https://public@example.invalid/1")
        #expect(reporter.configuration.debug)
    }
}
