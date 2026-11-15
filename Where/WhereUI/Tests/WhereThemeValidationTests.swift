import Testing
import ViewDocumentCore
@testable import WhereUI

struct WhereThemeValidationTests {
    @Test func rejectsPatternDivisorsAndExcessiveArtworkDensity() throws {
        for scale in [0.0, 1e-300, 0.24, 4.01] {
            #expect(throws: WhereThemeValidationError.self) {
                try WhereThemeValidation.validate(
                    scale,
                    path: "appearance.featureDiscovery.backgroundPattern.horizontalScale",
                )
            }
        }
        for center in [-0.1, 1.1, 10000] {
            #expect(throws: WhereThemeValidationError.self) {
                try WhereThemeValidation.validate(
                    center,
                    path: "appearance.featureDiscovery.backgroundPattern.centerXRatio",
                )
            }
        }
        #expect(throws: WhereThemeValidationError.self) {
            try WhereThemeValidation.validate(
                1e-300,
                path: "appearance.locationForecast.surface.microprintSpacing",
            )
        }
        #expect(throws: WhereThemeValidationError.self) {
            try WhereThemeValidation.validate(
                2.0,
                path: "appearance.locationsBackground.preferredCellSize",
            )
        }
        try WhereThemeValidation.validate(
            0.25,
            path: "appearance.featureDiscovery.backgroundPattern.horizontalScale",
        )
        try WhereThemeValidation.validate(
            2.0,
            path: "appearance.locationForecast.surface.microprintSpacing",
        )
        try WhereThemeValidation.validate(
            32.0,
            path: "appearance.locationsBackground.preferredCellSize",
        )
    }

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
