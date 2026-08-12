import Foundation
@testable import StuffToolCore
import Testing

struct TestHotSpotReportTests {
    @Test func aggregatesDurationsAndFlagsThresholds() throws {
        let catalog = try JSONDecoder().decode(
            XCResultTestCatalog.self,
            from: fixtureData("xcresult-tests", extension: "json"),
        )

        let text = TestHotSpotReport(catalogs: [catalog]).text(top: 1, threshold: 0.1)

        #expect(text.contains("2 tests, summed self-time 0.25s"))
        #expect(text.contains("0.200s  WhereCoreTests / fails()  <== over threshold"))
        #expect(text.contains("0.250s  WhereCoreTests (2 tests)"))
        #expect(text.contains("1 test(s) at/over the 0.1s threshold"))
        #expect(text.contains("works()") == false)
    }
}
