import Foundation
import Testing
@testable import ThrowUI

struct RelativeDatePresentationTests {
    @Test func formatsAgainstTheInjectedReferenceDate() {
        let referenceDate = Date(timeIntervalSince1970: 1_787_594_400)
        let locale = Locale(identifier: "en_US")
        let calendar = Calendar(identifier: .gregorian)

        #expect(
            RelativeDatePresentation.string(
                for: referenceDate,
                relativeTo: referenceDate,
                locale: locale,
                calendar: calendar,
            ) == "now",
        )
        #expect(
            RelativeDatePresentation.string(
                for: referenceDate.addingTimeInterval(3600),
                relativeTo: referenceDate,
                locale: locale,
                calendar: calendar,
            ) == "in 1 hour",
        )
        #expect(
            RelativeDatePresentation.string(
                for: referenceDate.addingTimeInterval(-3600),
                relativeTo: referenceDate,
                locale: locale,
                calendar: calendar,
            ) == "1 hour ago",
        )
    }
}
