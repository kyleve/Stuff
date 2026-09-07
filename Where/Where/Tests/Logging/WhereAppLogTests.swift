import PeriscopeCore
import Testing
@testable import Where

struct WhereAppLogTests {
    @Test func diagnosticProviderStartupFailureIsAnError() {
        let event = WhereAppLog.diagnosticProviderStartupFailed

        #expect(event.level == .error)
        #expect(event.message == "The diagnostic reporting provider did not start.")
    }
}
