import Foundation
import Testing
@testable import WhereUI

@MainActor
struct WhereThemeAppIconStylePatchTests {
    @Test(arguments: [-150.0, -149.999999999, -1])
    func rejectsNegativeGridColumnSpacing(_ spacing: Double) throws {
        var appearance = WhereThemeAppearance()
        appearance.appIcon = .init()
        appearance.appIcon?.columnSpacing = .constant(spacing)
        #expect(throws: WhereThemeValidationError.self) {
            try resolveTheme(
                themeDocument(appearance: appearance, fallback: .standard),
                traits: .system,
            )
        }
    }

    @Test func zeroGridColumnSpacingRemainsUsable() throws {
        var appearance = WhereThemeAppearance()
        appearance.appIcon = .init()
        appearance.appIcon?.columnSpacing = .constant(0)
        let sheet = try resolveTheme(
            themeDocument(appearance: appearance, fallback: .standard),
            traits: .system,
        )
        let metrics = AppIconLayout.gridMetrics(containerWidth: 390, style: sheet.appIcon)
        #expect(metrics.columnCount == 2)
        #expect(metrics.iconSize.isFinite && metrics.iconSize > 0)
    }

    @Test func changesOnlyAuthoredFieldsAfterRoundTrip() throws {
        try verifyThemePatch(
            json: #"{"appIcon":{"gridMax":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.appIcon.gridMax,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"appIcon":{"previewMax":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.appIcon.previewMax,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"appIcon":{"gridSpacing":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.appIcon.gridSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"appIcon":{"columnSpacing":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.appIcon.columnSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"appIcon":{"gridPadding":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.appIcon.gridPadding,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"appIcon":{"cellSpacing":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.appIcon.cellSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"appIcon":{"cellLabelSpacing":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.appIcon.cellLabelSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"appIcon":{"backgroundedCellOpacity":{"constant":{"_0":0.25}}}}"#,
            keyPath: \WhereStylesheet.appIcon.backgroundedCellOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"appIcon":{"panel":{"spacing":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.appIcon.panel.spacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"appIcon":{"panel":{"textSpacing":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.appIcon.panel.textSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"appIcon":{"panel":{"horizontalPadding":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.appIcon.panel.horizontalPadding,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"appIcon":{"panel":{"bottomPadding":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.appIcon.panel.bottomPadding,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"appIcon":{"panel":{"cornerRadius":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.appIcon.panel.cornerRadius,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"appIcon":{"panel":{"shadowRadius":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.appIcon.panel.shadowRadius,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"appIcon":{"panel":{"shadowOffsetY":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.appIcon.panel.shadowOffsetY,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"appIcon":{"panel":{"grabberOpacity":{"constant":{"_0":0.25}}}}}"#,
            keyPath: \WhereStylesheet.appIcon.panel.grabberOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"appIcon":{"panel":{"grabberTopPadding":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.appIcon.panel.grabberTopPadding,
            replacement: 42,
        )
    }
}
