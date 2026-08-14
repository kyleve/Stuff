import PeriscopeCore
import Testing
@testable import Where

struct WhereAppLogTests {
    @Test func diagnosticProviderStartupFailureIsAnError() {
        let event = WhereAppLog.DiagnosticProviderStartupFailed()

        #expect(
            WhereAppLog.DiagnosticProviderStartupFailed.eventName
                == "WhereApp.diagnostic-provider-startup-failed",
        )
        #expect(event.level == .error)
        #expect(event.message == "The diagnostic reporting provider did not start.")
        #expect(event.classifiedFields.isEmpty)
    }
}
