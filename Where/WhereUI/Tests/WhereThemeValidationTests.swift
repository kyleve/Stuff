import Testing
import ViewDocumentCore
@testable import WhereUI

struct WhereThemeValidationTests {
    @Test func descriptorFailureRetainsTheAppearancePathAndUnderlyingError() throws {
        do {
            try WhereThemeValidation.validate(
                ViewFontDescriptor(size: .fixed(-1), weight: nil, design: nil),
                path: "appearance.typography.widgetHeroRegion",
            )
            Issue.record("Expected invalid font rejection")
        } catch let error as WhereThemeValidationError {
            #expect(error.path == "appearance.typography.widgetHeroRegion")
            #expect(error.underlying != nil)
        }
    }

    @Test func rejectsUnboundedPatternDensityAndInvalidTypography() throws {
        for spacing in [0.0, 0.00001, -1, .infinity, .nan] {
            #expect(throws: WhereThemeValidationError.self) {
                try WhereThemeValidation.validate(
                    spacing,
                    path: "appearance.card.regular.rosette.primaryRingSpacing",
                )
            }
        }
        #expect(throws: WhereThemeValidationError.self) {
            try WhereThemeValidation.validate(
                WhereThemeAppearance.CardStyle.Typography.Size.fixed(-1),
                path: "font",
            )
        }
        try WhereThemeValidation.validate(0.0, path: "glow.opacity")
        try WhereThemeValidation.validate(-5.0, path: "artwork.offsetY")
    }
}
