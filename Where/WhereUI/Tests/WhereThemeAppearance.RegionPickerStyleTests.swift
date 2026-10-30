import Foundation
import Testing
@testable import WhereUI

@MainActor
struct WhereThemeRegionPickerStylePatchTests {
    @Test func geographicCentersAcceptWesternAndSouthernCoordinates() throws {
        var appearance = WhereThemeAppearance()
        appearance.regionPicker = .init()
        appearance.regionPicker?.mapCenterLatitude = .constant(-33.86)
        appearance.regionPicker?.mapCenterLongitude = .constant(-98.35)
        let sheet = try resolveTheme(
            themeDocument(appearance: appearance, fallback: .standard),
            traits: .system,
        )
        #expect(sheet.regionPicker.mapCenterLatitude == -33.86)
        #expect(sheet.regionPicker.mapCenterLongitude == -98.35)
    }

    @Test func rejectsInvalidGeographicCentersAndSpans() throws {
        for latitude in [-90.01, 90.01] {
            var appearance = WhereThemeAppearance()
            appearance.regionPicker = .init()
            appearance.regionPicker?.mapCenterLatitude = .constant(latitude)
            #expect(throws: WhereThemeValidationError.self) {
                try resolveTheme(
                    themeDocument(appearance: appearance, fallback: .standard),
                    traits: .system,
                )
            }
        }
        for longitude in [-180.01, 180.01] {
            var appearance = WhereThemeAppearance()
            appearance.regionPicker = .init()
            appearance.regionPicker?.mapCenterLongitude = .constant(longitude)
            #expect(throws: WhereThemeValidationError.self) {
                try resolveTheme(
                    themeDocument(appearance: appearance, fallback: .standard),
                    traits: .system,
                )
            }
        }
        for span in [0.0, -1, 180.01] {
            var appearance = WhereThemeAppearance()
            appearance.regionPicker = .init()
            appearance.regionPicker?.mapSpanLatitude = .constant(span)
            #expect(throws: WhereThemeValidationError.self) {
                _ = try resolveTheme(
                    themeDocument(appearance: appearance, fallback: .standard),
                    traits: .system,
                )
            }
        }
        for span in [0.0, -1, 360.01] {
            var appearance = WhereThemeAppearance()
            appearance.regionPicker = .init()
            appearance.regionPicker?.mapSpanLongitude = .constant(span)
            #expect(throws: WhereThemeValidationError.self) {
                try resolveTheme(
                    themeDocument(appearance: appearance, fallback: .standard),
                    traits: .system,
                )
            }
        }
    }

    @Test func changesOnlyAuthoredFieldsAfterRoundTrip() throws {
        try verifyThemePatch(
            json: #"{"regionPicker":{"mapCornerRadius":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.regionPicker.mapCornerRadius,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"regionPicker":{"selectedFillOpacity":{"constant":{"_0":0.25}}}}"#,
            keyPath: \WhereStylesheet.regionPicker.selectedFillOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"regionPicker":{"unselectedFillOpacity":{"constant":{"_0":0.25}}}}"#,
            keyPath: \WhereStylesheet.regionPicker.unselectedFillOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"regionPicker":{"selectedStrokeOpacity":{"constant":{"_0":0.25}}}}"#,
            keyPath: \WhereStylesheet.regionPicker.selectedStrokeOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"regionPicker":{"unselectedStrokeOpacity":{"constant":{"_0":0.25}}}}"#,
            keyPath: \WhereStylesheet.regionPicker.unselectedStrokeOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"regionPicker":{"selectedStrokeWidth":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.regionPicker.selectedStrokeWidth,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"regionPicker":{"unselectedStrokeWidth":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.regionPicker.unselectedStrokeWidth,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"regionPicker":{"colorSwatchSize":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.regionPicker.colorSwatchSize,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"regionPicker":{"colorSwatchSelectionRing":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.regionPicker.colorSwatchSelectionRing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"regionPicker":{"colorSwatchMinWidth":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.regionPicker.colorSwatchMinWidth,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"regionPicker":{"glyphTileSize":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.regionPicker.glyphTileSize,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"regionPicker":{"glyphTileMinWidth":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.regionPicker.glyphTileMinWidth,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"regionPicker":{"glyphCornerRadius":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.regionPicker.glyphCornerRadius,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"regionPicker":{"glyphSelectionStrokeWidth":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.regionPicker.glyphSelectionStrokeWidth,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"regionPicker":{"glyphSelectedBackgroundOpacity":{"constant":{"_0":0.25}}}}"#,
            keyPath: \WhereStylesheet.regionPicker.glyphSelectedBackgroundOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"regionPicker":{"mapCenterLatitude":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.regionPicker.mapCenterLatitude,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"regionPicker":{"mapCenterLongitude":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.regionPicker.mapCenterLongitude,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"regionPicker":{"mapSpanLatitude":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.regionPicker.mapSpanLatitude,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"regionPicker":{"mapSpanLongitude":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.regionPicker.mapSpanLongitude,
            replacement: 42,
        )
    }
}
