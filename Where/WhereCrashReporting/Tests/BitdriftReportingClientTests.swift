import Testing
@testable import WhereCrashReporting

@MainActor
struct BitdriftReportingClientTests {
    @Test func doesNotStartTheSDKInsideATestProcess() {
        let client = BitdriftReportingClient(
            apiKey: "public-client-key",
            environment: [
                "XCTestConfigurationFilePath": "/tmp/tests.xctestconfiguration",
            ],
            writer: RecordingWriter(),
            startupFailure: { _ in },
        )

        client.start(configuration: BitdriftLaunchConfiguration(
            enablesFatalIssueReporting: true,
            enablesSessionReplay: false,
        ))

        #expect(client.hasStarted == false)
    }

    @Test func launchConfigurationKeepsCrashAndReplayIndependent() {
        #expect(BitdriftLaunchConfiguration(
            enablesFatalIssueReporting: true,
            enablesSessionReplay: false,
        ) != BitdriftLaunchConfiguration(
            enablesFatalIssueReporting: false,
            enablesSessionReplay: true,
        ))
    }
}

private actor RecordingWriter: BitdriftLogWriting {
    func write(_: BitdriftLogEntry) {}
}
