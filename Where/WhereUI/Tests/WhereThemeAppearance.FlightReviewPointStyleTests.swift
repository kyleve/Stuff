import Foundation
import Testing
@testable import WhereUI

@MainActor
struct WhereThemeFlightReviewPointStylePatchTests {
    @Test func changesOnlyAuthoredFieldsAfterRoundTrip() throws {
        try verifyThemePatch(
            json: #"{"flightReviewPoint":{"minimumActionHeight":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.flightReviewPoint.minimumActionHeight,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"flightReviewPoint":{"mapCornerRadius":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.flightReviewPoint.mapCornerRadius,
            replacement: 42,
        )
    }
}
