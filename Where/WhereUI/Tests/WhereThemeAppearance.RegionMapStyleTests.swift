import Foundation
import Testing
@testable import WhereUI

@MainActor
struct WhereThemeRegionMapStylePatchTests {
    @Test(arguments: [0.0, 50000.0])
    func meterSpansAcceptTheNativeDefaults(_ span: Double) throws {
        var appearance = WhereThemeAppearance()
        appearance.regionMap = .init()
        appearance.regionMap?.pointPreview = .init()
        appearance.regionMap?.pointPreview?.minimumSpanMeters = .constant(span)
        let sheet = try resolveTheme(
            themeDocument(appearance: appearance, fallback: .standard),
            traits: .system,
        )
        #expect(sheet.regionMap.pointPreview.minimumSpanMeters == span)
    }

    @Test func changesOnlyAuthoredFieldsAfterRoundTrip() throws {
        try verifyThemePatch(
            json: #"{"regionMap":{"uncertaintyFillOpacity":{"constant":{"_0":0.25}}}}"#,
            keyPath: \WhereStylesheet.regionMap.uncertaintyFillOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"regionMap":{"uncertaintyStrokeOpacity":{"constant":{"_0":0.25}}}}"#,
            keyPath: \WhereStylesheet.regionMap.uncertaintyStrokeOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"regionMap":{"uncertaintyStrokeWidth":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.regionMap.uncertaintyStrokeWidth,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"regionMap":{"routeLineWidth":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.regionMap.routeLineWidth,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"regionMap":{"capturePointDiameter":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.regionMap.capturePointDiameter,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"regionMap":{"captureInset":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.regionMap.captureInset,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"regionMap":{"overview":{"height":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.regionMap.overview.height,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"regionMap":{"overview":{"minimumSpanMeters":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.regionMap.overview.minimumSpanMeters,
            replacement: 42,
        )
    }
}
