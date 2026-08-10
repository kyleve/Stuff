import Foundation
import StuffToolCore
import Testing

struct XCResultNodeTests {
    @Test func walksNestedFailuresAndBuildsUsableSuiteFilters() throws {
        let data = try fixtureData("xcresult-tests", extension: "json")

        let catalog = try JSONDecoder().decode(XCResultTestCatalog.self, from: data)

        #expect(catalog.failures == [
            FailedTest(
                label: "WhereCoreTests/CalendarDayTests/fails()",
                rerunIdentifier: "WhereCoreTests/CalendarDayTests",
            ),
        ])
    }
}
