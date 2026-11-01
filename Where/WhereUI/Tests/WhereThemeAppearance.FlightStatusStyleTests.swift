import Foundation
import Testing
@testable import WhereUI

@MainActor
struct WhereThemeFlightStatusStylePatchTests {
    @Test func changesOnlyAuthoredFieldsAfterRoundTrip() throws {
        try verifyThemePatch(
            json: #"{"flightStatus":{"padding":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.flightStatus.padding,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"flightStatus":{"spacing":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.flightStatus.spacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"flightStatus":{"cornerRadius":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.flightStatus.cornerRadius,
            replacement: 42,
        )
    }
}
