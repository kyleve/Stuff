import PeriscopeCore
import Testing
@_spi(Testing) import WhereCore
@testable import WhereUI

/// Pins the structured activation diagnostic used to explain a transient
/// Locations loading screen after the fact.
struct YearReportModelLogTests {
    @Test func activationRecordsItsTriggerAndPriorReportState() {
        let event = YearReportModelLog.activationStarted(
            year: 2026,
            trigger: "foreground-return",
            isFirstActivation: false,
            hadReport: true,
        )

        #expect(event.level == .info)
        #expect(event.externalID == WhereStoreID.year(2026))
        #expect(event.message == "Year report activation started for 2026"
            + " (trigger: foreground-return, first: false, had report: true)")
    }
}
