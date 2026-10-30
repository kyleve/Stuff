import Foundation
import Testing
@testable import WhereUI

@MainActor
struct WhereThemeStampBannerStylePatchTests {
    @Test func changesOnlyAuthoredFieldsAfterRoundTrip() throws {
        try verifyThemePatch(
            json: #"{"openSourceStamp":{"padding":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.openSourceStamp.padding,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"openSourceStamp":{"contentSpacing":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.openSourceStamp.contentSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"openSourceStamp":{"outlineWidth":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.openSourceStamp.outlineWidth,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"openSourceStamp":{"rosette":{"wobble":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.openSourceStamp.rosette.wobble,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"openSourceStamp":{"rosette":{"lineWidth":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.openSourceStamp.rosette.lineWidth,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"openSourceStamp":{"rosette":{"primaryRingSpacing":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.openSourceStamp.rosette.primaryRingSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"openSourceStamp":{"rosette":{"secondaryRingSpacing":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.openSourceStamp.rosette.secondaryRingSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"openSourceStamp":{"ink":{"outlineOpacity":{"constant":{"_0":0.25}}}}}"#,
            keyPath: \WhereStylesheet.openSourceStamp.ink.outlineOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"openSourceStamp":{"ink":{"primaryRosetteOpacity":{"constant":{"_0":0.25}}}}}"#,
            keyPath: \WhereStylesheet.openSourceStamp.ink.primaryRosetteOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"openSourceStamp":{"ink":{"secondaryRosetteOpacity":{"constant":{"_0":0.25}}}}}"#,
            keyPath: \WhereStylesheet.openSourceStamp.ink.secondaryRosetteOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"openSourceStamp":{"ink":{"sealOpacity":{"constant":{"_0":0.25}}}}}"#,
            keyPath: \WhereStylesheet.openSourceStamp.ink.sealOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"openSourceStamp":{"ink":{"titleOpacity":{"constant":{"_0":0.25}}}}}"#,
            keyPath: \WhereStylesheet.openSourceStamp.ink.titleOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"openSourceStamp":{"ink":{"detailOpacity":{"constant":{"_0":0.25}}}}}"#,
            keyPath: \WhereStylesheet.openSourceStamp.ink.detailOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"openSourceStamp":{"ink":{"accessoryOpacity":{"constant":{"_0":0.25}}}}}"#,
            keyPath: \WhereStylesheet.openSourceStamp.ink.accessoryOpacity,
            replacement: 0.25,
        )
    }
}
