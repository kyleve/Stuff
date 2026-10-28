import Testing
@testable import WhereCrashReporting

struct CrashReportingProcessTests {
    @Test func skipsXCTestProcesses() {
        #expect(CrashReportingProcess.shouldStart(environment: [
            "XCTestConfigurationFilePath": "/tmp/tests.xctestconfiguration",
        ]) == false)
    }

    @Test func startsOrdinaryApplicationProcesses() {
        #expect(CrashReportingProcess.shouldStart(environment: [:]))
    }
}
