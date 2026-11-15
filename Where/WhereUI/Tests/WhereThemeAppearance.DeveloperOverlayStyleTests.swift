import Foundation
import Testing
@testable import WhereUI

@MainActor
struct WhereThemeDeveloperOverlayStylePatchTests {
    @Test func changesOnlyAuthoredFieldsAfterRoundTrip() throws {
        try verifyThemePatch(
            json: #"{"developerOverlay":{"edgeInset":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.developerOverlay.edgeInset,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"developerOverlay":{"launcher":{"diameter":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.developerOverlay.launcher.diameter,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"developerOverlay":{"launcher":{"glyphRatio":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.developerOverlay.launcher.glyphRatio,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"developerOverlay":{"launcher":{"shadowRadius":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.developerOverlay.launcher.shadowRadius,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"developerOverlay":{"launcher":{"shadowOffsetY":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.developerOverlay.launcher.shadowOffsetY,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"developerOverlay":{"floatingWindow":{"maxWidth":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.developerOverlay.floatingWindow.maxWidth,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"developerOverlay":{"floatingWindow":{"maxHeight":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.developerOverlay.floatingWindow.maxHeight,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"developerOverlay":{"floatingWindow":{"heightFraction":{"constant":{"_0":0.25}}}}}"#,
            keyPath: \WhereStylesheet.developerOverlay.floatingWindow.heightFraction,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"developerOverlay":{"floatingWindow":{"maxContentInsetFraction":{"constant":{"_0":0.25}}}}}"#,
            keyPath: \WhereStylesheet.developerOverlay.floatingWindow.maxContentInsetFraction,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"developerOverlay":{"panel":{"cornerRadius":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.developerOverlay.panel.cornerRadius,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"developerOverlay":{"panel":{"fullScreenInset":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.developerOverlay.panel.fullScreenInset,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"developerOverlay":{"panel":{"shadowOpacity":{"constant":{"_0":0.25}}}}}"#,
            keyPath: \WhereStylesheet.developerOverlay.panel.shadowOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"developerOverlay":{"panel":{"shadowRadius":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.developerOverlay.panel.shadowRadius,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"developerOverlay":{"panel":{"shadowOffsetY":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.developerOverlay.panel.shadowOffsetY,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"developerOverlay":{"panel":{"controlHorizontalPadding":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.developerOverlay.panel.controlHorizontalPadding,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"developerOverlay":{"panel":{"controlVerticalPadding":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.developerOverlay.panel.controlVerticalPadding,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"developerOverlay":{"panel":{"dragHandleMinHeight":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.developerOverlay.panel.dragHandleMinHeight,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"developerOverlay":{"panel":{"resizeGripSize":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.developerOverlay.panel.resizeGripSize,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"developerOverlay":{"panel":{"resizeIconSize":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.developerOverlay.panel.resizeIconSize,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"developerOverlay":{"panel":{"resizeGripClearance":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.developerOverlay.panel.resizeGripClearance,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"developerOverlay":{"menu":{"maxWidth":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.developerOverlay.menu.maxWidth,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"developerOverlay":{"menu":{"launcherSpacing":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.developerOverlay.menu.launcherSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"developerOverlay":{"menu":{"rowSpacing":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.developerOverlay.menu.rowSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"developerOverlay":{"menu":{"horizontalPadding":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.developerOverlay.menu.horizontalPadding,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"developerOverlay":{"menu":{"verticalPadding":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.developerOverlay.menu.verticalPadding,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"developerOverlay":{"menu":{"minRowHeight":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.developerOverlay.menu.minRowHeight,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"developerOverlay":{"menu":{"cornerRadius":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.developerOverlay.menu.cornerRadius,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"developerOverlay":{"menu":{"subtitleSpacing":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.developerOverlay.menu.subtitleSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"developerOverlay":{"menu":{"iconWidth":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.developerOverlay.menu.iconWidth,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"developerOverlay":{"menu":{"motion":{"stagger":{"constant":{"_0":42}}}}}}"#,
            keyPath: \WhereStylesheet.developerOverlay.menu.motion.stagger,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"developerOverlay":{"menu":{"motion":{"scale":{"constant":{"_0":42}}}}}}"#,
            keyPath: \WhereStylesheet.developerOverlay.menu.motion.scale,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"developerOverlay":{"menu":{"motion":{"usesSpatialMotion":{"constant":{"_0":false}}}}}}"#,
            keyPath: \WhereStylesheet.developerOverlay.menu.motion.usesSpatialMotion,
            replacement: false,
        )
    }
}
