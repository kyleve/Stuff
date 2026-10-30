import Foundation
import Testing
@testable import WhereUI

@MainActor
struct WhereThemeCardStylesPatchTests {
    @Test func changesOnlyAuthoredFieldsAfterRoundTrip() throws {
        try verifyThemePatch(
            json: #"{"card":{"watermarkOpacity":{"constant":{"_0":0.25}}}}"#,
            keyPath: \WhereStylesheet.card.watermarkOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"card":{"glassTintOpacity":{"constant":{"_0":0.25}}}}"#,
            keyPath: \WhereStylesheet.card.glassTintOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"card":{"nameOpacity":{"constant":{"_0":0.25}}}}"#,
            keyPath: \WhereStylesheet.card.nameOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"card":{"estimatedProgressOpacity":{"constant":{"_0":0.25}}}}"#,
            keyPath: \WhereStylesheet.card.estimatedProgressOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"card":{"estimateSticker":{"contentOpacity":{"constant":{"_0":0.25}}}}}"#,
            keyPath: \WhereStylesheet.card.estimateSticker.contentOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"card":{"estimateSticker":{"scale":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.card.estimateSticker.scale,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"card":{"estimateSticker":{"cornerRadius":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.card.estimateSticker.cornerRadius,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"card":{"estimateSticker":{"horizontalPadding":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.card.estimateSticker.horizontalPadding,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"card":{"estimateSticker":{"verticalPadding":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.card.estimateSticker.verticalPadding,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"card":{"estimateSticker":{"rotationDegrees":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.card.estimateSticker.rotationDegrees,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"card":{"estimateSticker":{"fillOpacity":{"constant":{"_0":0.25}}}}}"#,
            keyPath: \WhereStylesheet.card.estimateSticker.fillOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"card":{"estimateSticker":{"outlineOpacity":{"constant":{"_0":0.25}}}}}"#,
            keyPath: \WhereStylesheet.card.estimateSticker.outlineOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"card":{"estimateSticker":{"outlineWidth":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.card.estimateSticker.outlineWidth,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"card":{"estimateSticker":{"innerInset":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.card.estimateSticker.innerInset,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"card":{"estimateSticker":{"innerOutlineWidth":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.card.estimateSticker.innerOutlineWidth,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"card":{"rosetteFill":{"primary":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.card.rosetteFill.primary,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"card":{"rosetteFill":{"secondary":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.card.rosetteFill.secondary,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"card":{"securityPrint":{"whiteMix":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.card.securityPrint.whiteMix,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"card":{"constellation":{"coreDiameter":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.card.constellation.coreDiameter,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"card":{"constellation":{"coreOpacity":{"constant":{"_0":0.25}}}}}"#,
            keyPath: \WhereStylesheet.card.constellation.coreOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"card":{"constellation":{"coreWhiteMix":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.card.constellation.coreWhiteMix,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"card":{"constellation":{"haloRadius":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.card.constellation.haloRadius,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"card":{"constellation":{"haloOpacity":{"constant":{"_0":0.25}}}}}"#,
            keyPath: \WhereStylesheet.card.constellation.haloOpacity,
            replacement: 0.25,
        )
    }
}
