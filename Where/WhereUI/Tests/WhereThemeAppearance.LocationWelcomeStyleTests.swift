import Foundation
import Testing
@testable import WhereUI

@MainActor
struct WhereThemeLocationWelcomeStylePatchTests {
    @Test func changesOnlyAuthoredFieldsAfterRoundTrip() throws {
        try verifyThemePatch(
            json: #"{"locationWelcome":{"maxWidth":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.locationWelcome.maxWidth,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationWelcome":{"cornerRadius":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.locationWelcome.cornerRadius,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationWelcome":{"padding":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.locationWelcome.padding,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationWelcome":{"contentSpacing":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.locationWelcome.contentSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationWelcome":{"paperOpacity":{"constant":{"_0":0.25}}}}"#,
            keyPath: \WhereStylesheet.locationWelcome.paperOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"locationWelcome":{"scrimOpacity":{"constant":{"_0":0.25}}}}"#,
            keyPath: \WhereStylesheet.locationWelcome.scrimOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"locationWelcome":{"glassTintOpacity":{"constant":{"_0":0.25}}}}"#,
            keyPath: \WhereStylesheet.locationWelcome.glassTintOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"locationWelcome":{"glow":{"opacity":{"constant":{"_0":0.25}}}}}"#,
            keyPath: \WhereStylesheet.locationWelcome.glow.opacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"locationWelcome":{"glow":{"radius":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.locationWelcome.glow.radius,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationWelcome":{"glow":{"offsetY":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.locationWelcome.glow.offsetY,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationWelcome":{"close":{"tintOpacity":{"constant":{"_0":0.25}}}}}"#,
            keyPath: \WhereStylesheet.locationWelcome.close.tintOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"locationWelcome":{"accessory":{"contentSpacing":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.locationWelcome.accessory.contentSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationWelcome":{"accessory":{"horizontalPadding":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.locationWelcome.accessory.horizontalPadding,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationWelcome":{"accessory":{"verticalPadding":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.locationWelcome.accessory.verticalPadding,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationWelcome":{"accessory":{"minimumActionHeight":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.locationWelcome.accessory.minimumActionHeight,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationWelcome":{"accessory":{"symbolSize":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.locationWelcome.accessory.symbolSize,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationWelcome":{"motion":{"usesSpatialMotion":{"constant":{"_0":false}}}}}"#,
            keyPath: \WhereStylesheet.locationWelcome.motion.usesSpatialMotion,
            replacement: false,
        )
        try verifyThemePatch(
            json: #"{"locationWelcome":{"motion":{"arrival":{"scale":{"constant":{"_0":42}}}}}}"#,
            keyPath: \WhereStylesheet.locationWelcome.motion.arrival.scale,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationWelcome":{"motion":{"arrival":{"rotationDegrees":{"constant":{"_0":42}}}}}}"#,
            keyPath: \WhereStylesheet.locationWelcome.motion.arrival.rotationDegrees,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"locationWelcome":{"motion":{"arrival":{"verticalOffset":{"constant":{"_0":42}}}}}}"#,
            keyPath: \WhereStylesheet.locationWelcome.motion.arrival.verticalOffset,
            replacement: 42,
        )
    }
}
