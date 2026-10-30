import Foundation
import Testing
@testable import WhereUI

@MainActor
struct WhereThemeCardStylePatchTests {
    @Test func changesOnlyAuthoredFieldsAfterRoundTrip() throws {
        try verifyThemePatch(
            json: #"{"card":{"regular":{"cornerRadius":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.card.regular.cornerRadius,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"card":{"regular":{"padding":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.card.regular.padding,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"card":{"regular":{"contentSpacing":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.card.regular.contentSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"card":{"regular":{"progressBarHeight":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.card.regular.progressBarHeight,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"card":{"regular":{"regionNameTracking":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.card.regular.regionNameTracking,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"card":{"regular":{"watermarkFontSize":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.card.regular.watermarkFontSize,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationsBackground":{"artwork":{"scale":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.locationsBackground.artwork.scale,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationsBackground":{"artwork":{"fillOpacity":{"constant":{"_0":0.25}}}}}"#,
            keyPath: \WhereStylesheet.locationsBackground.artwork.fillOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"locationsBackground":{"rosette":{"wobble":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.locationsBackground.rosette.wobble,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationsBackground":{"rosette":{"lineWidth":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.locationsBackground.rosette.lineWidth,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationsBackground":{"rosette":{"primaryRingSpacing":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.locationsBackground.rosette.primaryRingSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationsBackground":{"rosette":{"secondaryRingSpacing":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.locationsBackground.rosette.secondaryRingSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"card":{"regular":{"entryStamp":{"size":{"constant":{"_0":42}}}}}}"#,
            keyPath: \WhereStylesheet.card.regular.entryStamp.size,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"card":{"regular":{"entryStamp":{"rotationDegrees":{"constant":{"_0":42}}}}}}"#,
            keyPath: \WhereStylesheet.card.regular.entryStamp.rotationDegrees,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"card":{"regular":{"sheen":{"intensity":{"constant":{"_0":42}}}}}}"#,
            keyPath: \WhereStylesheet.card.regular.sheen.intensity,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"card":{"regular":{"sheen":{"staticGlintIntensity":{"constant":{"_0":42}}}}}}"#,
            keyPath: \WhereStylesheet.card.regular.sheen.staticGlintIntensity,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"card":{"regular":{"glow":{"opacity":{"constant":{"_0":0.25}}}}}}"#,
            keyPath: \WhereStylesheet.card.regular.glow.opacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"card":{"regular":{"glow":{"radius":{"constant":{"_0":42}}}}}}"#,
            keyPath: \WhereStylesheet.card.regular.glow.radius,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"card":{"regular":{"glow":{"offsetY":{"constant":{"_0":42}}}}}}"#,
            keyPath: \WhereStylesheet.card.regular.glow.offsetY,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"summary":{"border":{"inset":{"constant":{"_0":42}}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.summary.border.inset,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"summary":{"border":{"glyphSize":{"constant":{"_0":42}}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.summary.border.glyphSize,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"summary":{"border":{"spacing":{"constant":{"_0":42}}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.summary.border.spacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationForecast":{"summary":{"border":{"opacity":{"constant":{"_0":0.25}}}}}}"#,
            keyPath: \WhereStylesheet.locationForecast.summary.border.opacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"card":{"regular":{"entryStamp":{"outerRing":{"opacity":{"constant":{"_0":0.25}}}}}}}"#,
            keyPath: \WhereStylesheet.card.regular.entryStamp.outerRing.opacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"card":{"regular":{"entryStamp":{"outerRing":{"lineWidthFraction":{"constant":{"_0":0.25}}}}}}}"#,
            keyPath: \WhereStylesheet.card.regular.entryStamp.outerRing.lineWidthFraction,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"card":{"regular":{"entryStamp":{"innerRing":{"opacity":{"constant":{"_0":0.25}}}}}}}"#,
            keyPath: \WhereStylesheet.card.regular.entryStamp.innerRing.opacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"card":{"regular":{"entryStamp":{"innerRing":{"lineWidthFraction":{"constant":{"_0":0.25}}}}}}}"#,
            keyPath: \WhereStylesheet.card.regular.entryStamp.innerRing.lineWidthFraction,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"card":{"regular":{"entryStamp":{"innerRing":{"insetFraction":{"constant":{"_0":0.25}}}}}}}"#,
            keyPath: \WhereStylesheet.card.regular.entryStamp.innerRing.insetFraction,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"card":{"regular":{"entryStamp":{"content":{"spacingFraction":{"constant":{"_0":0.25}}}}}}}"#,
            keyPath: \WhereStylesheet.card.regular.entryStamp.content.spacingFraction,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"card":{"regular":{"entryStamp":{"content":{"opacity":{"constant":{"_0":0.25}}}}}}}"#,
            keyPath: \WhereStylesheet.card.regular.entryStamp.content.opacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"card":{"regular":{"sheen":{"staticPose":{"roll":{"constant":{"_0":42}}}}}}}"#,
            keyPath: \WhereStylesheet.card.regular.sheen.staticPose.roll,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"card":{"regular":{"sheen":{"staticPose":{"pitch":{"constant":{"_0":42}}}}}}}"#,
            keyPath: \WhereStylesheet.card.regular.sheen.staticPose.pitch,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"card":{"regular":{"entryStamp":{"innerRing":{"dash":{"lengthFraction":{"constant":{"_0":0.25}}}}}}}}"#,
            keyPath: \WhereStylesheet.card.regular.entryStamp.innerRing.dash.lengthFraction,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"card":{"regular":{"entryStamp":{"innerRing":{"dash":{"spacingFraction":{"constant":{"_0":0.25}}}}}}}}"#,
            keyPath: \WhereStylesheet.card.regular.entryStamp.innerRing.dash.spacingFraction,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"card":{"regular":{"entryStamp":{"content":{"symbolFont":{"sizeFraction":{"constant":{"_0":0.25}}}}}}}}"#,
            keyPath: \WhereStylesheet.card.regular.entryStamp.content.symbolFont.sizeFraction,
            replacement: 0.25,
        )
    }
}
