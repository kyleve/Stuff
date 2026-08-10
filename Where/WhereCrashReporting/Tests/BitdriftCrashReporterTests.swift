import Testing
@testable import WhereCrashReporting

@MainActor
struct BitdriftCrashReporterTests {
    @Test func preservesBootstrapConfiguration() {
        let reporter = BitdriftCrashReporter(apiKey: "public-client-key")

        #expect(reporter.configuration.apiKey == "public-client-key")
    }
}
