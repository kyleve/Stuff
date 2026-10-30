import Foundation
import Testing
@testable import WhereUI

@MainActor
struct WhereThemeThemePickerStylePatchTests {
    @Test func changesOnlyAuthoredFieldsAfterRoundTrip() throws {
        try verifyThemePatch(
            json: #"{"themePicker":{"spacing":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.themePicker.spacing,
            replacement: 42,
        )
    }
}
