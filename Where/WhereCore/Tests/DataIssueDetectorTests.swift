import Foundation
import Testing
import WhereCore

private typealias Fixtures = DataIssueDetectorFixtures

/// Covers the `DataIssueDetecting`/`DataIssueDetector` protocols themselves; the
/// concrete detectors are exercised in their own `*DetectorTests` files.
struct DataIssueDetectorTests {
    @Test func detectAnyIssues_erasesToExistential() throws {
        let detector: any DataIssueDetecting = MissingDaysDetector()
        let issues = try detector.detectAnyIssues(in: Fixtures.input())
        #expect(!issues.isEmpty)
        #expect(issues.allSatisfy { $0.category == .missingDays })
    }
}
