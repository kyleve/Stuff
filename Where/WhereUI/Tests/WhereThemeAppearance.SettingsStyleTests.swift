import Foundation
import Testing
@testable import WhereUI

@MainActor
struct WhereThemeSettingsStylePatchTests {
    @Test func changesOnlyAuthoredFieldsAfterRoundTrip() throws {
        try verifyThemePatch(
            json: #"{"settings":{"iconSize":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.settings.iconSize,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"settings":{"iconCornerRadius":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.settings.iconCornerRadius,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"settings":{"iconSymbolSize":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.settings.iconSymbolSize,
            replacement: 42,
        )
    }
}
