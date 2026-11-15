import Foundation
import Testing
@testable import WhereUI

@MainActor
struct WhereThemeLocationForecastStylePatchTests {
    @Test func changesOnlyAuthoredFieldsAfterRoundTrip() throws {
        try verifyThemePatch(
            json: #"{"locationForecast":{"cornerRadius":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.cornerRadius,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"padding":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.padding,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"rowSpacing":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.rowSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"surface":{"outlineWidth":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.surface.outlineWidth,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"surface":{"inset":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.surface.inset,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"surface":{"microprintGlyphSize":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.surface.microprintGlyphSize,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"surface":{"microprintSpacing":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.surface.microprintSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"surface":{"rosetteWobble":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.surface.rosetteWobble,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"surface":{"rosetteLineWidth":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.surface.rosetteLineWidth,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"surface":{"primaryRingSpacing":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.surface.primaryRingSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"surface":{"secondaryRingSpacing":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.surface.secondaryRingSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"surface":{"shadowRadius":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.surface.shadowRadius,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"surface":{"shadowOffsetY":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.surface.shadowOffsetY,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"header":{"contentSpacing":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.header.contentSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"header":{"textSpacing":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.header.textSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"header":{"minimumHeight":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.header.minimumHeight,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"row":{"cornerRadius":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.row.cornerRadius,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"row":{"padding":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.row.padding,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"row":{"contentSpacing":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.row.contentSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"row":{"estimateSpacing":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.row.estimateSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"row":{"outlineWidth":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.row.outlineWidth,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"progress":{"height":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.progress.height,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"progress":{"hatchSpacing":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.progress.hatchSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"progress":{"hatchLineWidth":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.progress.hatchLineWidth,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"controls":{"sectionSpacing":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.controls.sectionSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"controls":{"layoutSpacing":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.controls.layoutSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"controls":{"cornerRadius":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.controls.cornerRadius,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"controls":{"horizontalPadding":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.controls.horizontalPadding,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"controls":{"minimumHeight":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.controls.minimumHeight,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"controls":{"strokeWidth":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.controls.strokeWidth,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"ink":{"surfaceWashOpacity":{"constant":{"_0":0.25}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.ink.surfaceWashOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"ink":{"surfaceOutlineOpacity":{"constant":{"_0":0.25}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.ink.surfaceOutlineOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"ink":{"microprintOpacity":{"constant":{"_0":0.25}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.ink.microprintOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"ink":{"rosettePrimaryOpacity":{"constant":{"_0":0.25}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.ink.rosettePrimaryOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"ink":{"rosetteSecondaryOpacity":{"constant":{"_0":0.25}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.ink.rosetteSecondaryOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"ink":{"sealOpacity":{"constant":{"_0":0.25}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.ink.sealOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"ink":{"rowFillOpacity":{"constant":{"_0":0.25}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.ink.rowFillOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"ink":{"rowOutlineOpacity":{"constant":{"_0":0.25}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.ink.rowOutlineOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"ink":{"progressTrackOpacity":{"constant":{"_0":0.25}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.ink.progressTrackOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"ink":{"progressEstimateFillOpacity":{"constant":{"_0":0.25}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.ink.progressEstimateFillOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"ink":{"progressHatchOpacity":{"constant":{"_0":0.25}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.ink.progressHatchOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"ink":{"controlFillOpacity":{"constant":{"_0":0.25}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.ink.controlFillOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"ink":{"controlStrokeOpacity":{"constant":{"_0":0.25}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.ink.controlStrokeOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"summary":{"cornerRadius":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.summary.cornerRadius,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"summary":{"padding":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.summary.padding,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"summary":{"usesOpaquePaper":{"constant":{"_0":false}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.summary.usesOpaquePaper,
            replacement: false,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"summary":{"glassTintOpacity":{"constant":{"_0":0.25}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.summary.glassTintOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"summary":{"outlineWidth":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.summary.outlineWidth,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"summary":{"shadowOpacity":{"constant":{"_0":0.25}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.summary.shadowOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"summary":{"shadowRadius":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.summary.shadowRadius,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"summary":{"shadowOffsetY":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.summary.shadowOffsetY,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"summary":{"rosetteOpacity":{"constant":{"_0":0.25}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.summary.rosetteOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"summary":{"artwork":{"widthFraction":{"constant":{"_0":0.25}}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.summary.artwork.widthFraction,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"summary":{"artwork":{"inset":{"constant":{"_0":42}}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.summary.artwork.inset,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"summary":{"artwork":{"gap":{"constant":{"_0":42}}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.summary.artwork.gap,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"summary":{"artwork":{"leadingOpacity":{"constant":{"_0":0.25}}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.summary.artwork.leadingOpacity,
            replacement: 0.25,
        )
    }
}
