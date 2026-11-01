import Testing
import ViewDocumentCore
@testable import WhereUI

@MainActor
struct WhereBundledThemeAssetsTests {
    @Test func missingApprovedIllustrationFailsPreparation() {
        #expect(throws: WhereThemeValidationError.self) {
            try WhereBundledThemeAssets.load(illustrations: [
                ViewAssetID(rawValue: "holiday.missing"): "MissingHolidayIllustration",
            ])
        }
    }
}
