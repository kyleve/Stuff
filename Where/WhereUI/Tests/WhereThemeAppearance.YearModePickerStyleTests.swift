import Testing
@testable import WhereUI

@MainActor
struct WhereThemeYearModePickerPatchTests {
    @Test func layoutOverridesRemainTyped() throws {
        try verifyThemePatch(
            json: #"{"yearModePicker":{"layout":{"constant":{"_0":{"stacked":{}}}}}}"#,
            keyPath: \WhereStylesheet.yearModePicker.layout,
            replacement: .stacked,
        )
    }
}
