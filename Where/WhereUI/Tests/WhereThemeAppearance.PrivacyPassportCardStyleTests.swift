import Foundation
import Testing
@testable import WhereUI

@MainActor
struct WhereThemePrivacyPassportCardStylePatchTests {
    @Test func changesOnlyAuthoredFieldsAfterRoundTrip() throws {
        try verifyThemePatch(
            json: #"{"privacyPassportCard":{"cornerRadius":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.privacyPassportCard.cornerRadius,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"privacyPassportCard":{"padding":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.privacyPassportCard.padding,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"privacyPassportCard":{"sectionSpacing":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.privacyPassportCard.sectionSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"privacyPassportCard":{"headerSpacing":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.privacyPassportCard.headerSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"privacyPassportCard":{"outlineOpacity":{"constant":{"_0":0.25}}}}"#,
            keyPath: \WhereStylesheet.privacyPassportCard.outlineOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"privacyPassportCard":{"outlineWidth":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.privacyPassportCard.outlineWidth,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"privacyPassportCard":{"rosette":{"wobble":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.privacyPassportCard.rosette.wobble,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"privacyPassportCard":{"rosette":{"lineWidth":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.privacyPassportCard.rosette.lineWidth,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"privacyPassportCard":{"rosette":{"primaryRingSpacing":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.privacyPassportCard.rosette.primaryRingSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"privacyPassportCard":{"rosette":{"secondaryRingSpacing":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.privacyPassportCard.rosette.secondaryRingSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"privacyPassportCard":{"rosette":{"primaryOpacity":{"constant":{"_0":0.25}}}}}"#,
            keyPath: \WhereStylesheet.privacyPassportCard.rosette.primaryOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"privacyPassportCard":{"rosette":{"secondaryOpacity":{"constant":{"_0":0.25}}}}}"#,
            keyPath: \WhereStylesheet.privacyPassportCard.rosette.secondaryOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"privacyPassportCard":{"reflectiveSurface":{"intensity":{"constant":{"_0":0.25}}}}}"#,
            keyPath: \WhereStylesheet.privacyPassportCard.reflectiveSurface.intensity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"privacyPassportCard":{"reflectiveSurface":{"staticGlintIntensity":{"constant":{"_0":0.25}}}}}"#,
            keyPath: \WhereStylesheet.privacyPassportCard.reflectiveSurface.staticGlintIntensity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"privacyPassportCard":{"disclosure":{"rowSpacing":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.privacyPassportCard.disclosure.rowSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"privacyPassportCard":{"disclosure":{"cornerRadius":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.privacyPassportCard.disclosure.cornerRadius,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"privacyPassportCard":{"disclosure":{"padding":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.privacyPassportCard.disclosure.padding,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"privacyPassportCard":{"disclosure":{"contentSpacing":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.privacyPassportCard.disclosure.contentSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"privacyPassportCard":{"disclosure":{"textSpacing":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.privacyPassportCard.disclosure.textSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"privacyPassportCard":{"disclosure":{"iconSize":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.privacyPassportCard.disclosure.iconSize,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"privacyPassportCard":{"disclosure":{"statusHorizontalPadding":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.privacyPassportCard.disclosure.statusHorizontalPadding,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"privacyPassportCard":{"disclosure":{"statusVerticalPadding":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.privacyPassportCard.disclosure.statusVerticalPadding,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"privacyPassportCard":{"disclosure":{"fillOpacity":{"constant":{"_0":0.25}}}}}"#,
            keyPath: \WhereStylesheet.privacyPassportCard.disclosure.fillOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"privacyPassportCard":{"disclosure":{"strokeOpacity":{"constant":{"_0":0.25}}}}}"#,
            keyPath: \WhereStylesheet.privacyPassportCard.disclosure.strokeOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"privacyPassportCard":{"disclosure":{"strokeWidth":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.privacyPassportCard.disclosure.strokeWidth,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"privacyPassportCard":{"disclosure":{"statusFillOpacity":{"constant":{"_0":0.25}}}}}"#,
            keyPath: \WhereStylesheet.privacyPassportCard.disclosure.statusFillOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"privacyPassportCard":{"reflectiveSurface":{"staticPose":{"roll":{"constant":{"_0":42}}}}}}"#,
            keyPath: \WhereStylesheet.privacyPassportCard.reflectiveSurface.staticPose.roll,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"privacyPassportCard":{"reflectiveSurface":{"staticPose":{"pitch":{"constant":{"_0":42}}}}}}"#,
            keyPath: \WhereStylesheet.privacyPassportCard.reflectiveSurface.staticPose.pitch,
            replacement: 42,
        )
    }
}
