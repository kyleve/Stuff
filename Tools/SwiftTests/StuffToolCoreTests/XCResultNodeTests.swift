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
        #expect(catalog.testCases == [
            XCResultTestCase(
                identifier: "WhereCoreTests/CalendarDayTests/works()",
                bundle: "WhereCoreTests",
                name: "works()",
                result: "Passed",
                durationInSeconds: 0.05,
            ),
            XCResultTestCase(
                identifier: "WhereCoreTests/CalendarDayTests/fails()",
                bundle: "WhereCoreTests",
                name: "fails()",
                result: "Failed",
                durationInSeconds: 0.2,
            ),
        ])
    }
}
