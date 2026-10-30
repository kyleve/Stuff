import Foundation
import Testing
@testable import WhereUI

@MainActor
struct WhereThemeLocationsBackgroundStylePatchTests {
    @Test func changesOnlyAuthoredFieldsAfterRoundTrip() throws {
        try verifyThemePatch(
            json: #"{"locationsBackground":{"showsInk":{"constant":{"_0":false}}}}"#,
            keyPath: \WhereStylesheet.locationsBackground.showsInk,
            replacement: false,
        )
        try verifyThemePatch(
            json: #"{"locationsBackground":{"preferredCellSize":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.locationsBackground.preferredCellSize,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationsBackground":{"maximumAspectScale":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.locationsBackground.maximumAspectScale,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationsBackground":{"rosetteOpacity":{"constant":{"_0":0.25}}}}"#,
            keyPath: \WhereStylesheet.locationsBackground.rosetteOpacity,
            replacement: 0.25,
        )
    }
}
