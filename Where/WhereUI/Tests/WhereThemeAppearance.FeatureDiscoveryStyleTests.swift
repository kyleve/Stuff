import Foundation
import Testing
@testable import WhereUI

@MainActor
struct WhereThemeFeatureDiscoveryStylePatchTests {
    @Test func changesOnlyAuthoredFieldsAfterRoundTrip() throws {
        try verifyThemePatch(
            json: #"{"featureDiscovery":{"appIcon":{"spacing":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.featureDiscovery.appIcon.spacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"featureDiscovery":{"regionStyle":{"spacing":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.featureDiscovery.regionStyle.spacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"featureDiscovery":{"shareSheet":{"sourcesSpacing":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.featureDiscovery.shareSheet.sourcesSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"featureDiscovery":{"evidenceArchive":{"spacing":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.featureDiscovery.evidenceArchive.spacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"featureDiscovery":{"marketingHeader":{"badgeSize":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.featureDiscovery.marketingHeader.badgeSize,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"featureDiscovery":{"marketingHeader":{"symbolPointSize":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.featureDiscovery.marketingHeader.symbolPointSize,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"featureDiscovery":{"marketingHeader":{"badgeTintOpacity":{"constant":{"_0":0.25}}}}}"#,
            keyPath: \WhereStylesheet.featureDiscovery.marketingHeader.badgeTintOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"featureDiscovery":{"marketingHeader":{"contentMaxWidth":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.featureDiscovery.marketingHeader.contentMaxWidth,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"featureDiscovery":{"marketingHeader":{"spacing":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.featureDiscovery.marketingHeader.spacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"featureDiscovery":{"marketingHeader":{"verticalPadding":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.featureDiscovery.marketingHeader.verticalPadding,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"featureDiscovery":{"marketingPanel":{"cornerRadius":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.featureDiscovery.marketingPanel.cornerRadius,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"featureDiscovery":{"marketingPanel":{"maxWidth":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.featureDiscovery.marketingPanel.maxWidth,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"featureDiscovery":{"marketingPanel":{"padding":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.featureDiscovery.marketingPanel.padding,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"featureDiscovery":{"marketingPanel":{"contentSpacing":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.featureDiscovery.marketingPanel.contentSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"featureDiscovery":{"marketingPanel":{"rowVerticalInset":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.featureDiscovery.marketingPanel.rowVerticalInset,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"featureDiscovery":{"backgroundPattern":{"contourSpacing":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.featureDiscovery.backgroundPattern.contourSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"featureDiscovery":{"backgroundPattern":{"primaryDistortion":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.featureDiscovery.backgroundPattern.primaryDistortion,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"featureDiscovery":{"backgroundPattern":{"secondaryDistortion":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.featureDiscovery.backgroundPattern.secondaryDistortion,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"featureDiscovery":{"backgroundPattern":{"horizontalScale":{"constant":{"_0":1.4}}}}}"#,
            keyPath: \WhereStylesheet.featureDiscovery.backgroundPattern.horizontalScale,
            replacement: 1.4,
        )
        try verifyThemePatch(
            json: #"{"featureDiscovery":{"backgroundPattern":{"centerXRatio":{"constant":{"_0":0.3}}}}}"#,
            keyPath: \WhereStylesheet.featureDiscovery.backgroundPattern.centerXRatio,
            replacement: 0.3,
        )
        try verifyThemePatch(
            json: #"{"featureDiscovery":{"backgroundPattern":{"centerYRatio":{"constant":{"_0":0.7}}}}}"#,
            keyPath: \WhereStylesheet.featureDiscovery.backgroundPattern.centerYRatio,
            replacement: 0.7,
        )
        try verifyThemePatch(
            json: #"{"featureDiscovery":{"backgroundPattern":{"phaseStep":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.featureDiscovery.backgroundPattern.phaseStep,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"featureDiscovery":{"backgroundPattern":{"lineWidth":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.featureDiscovery.backgroundPattern.lineWidth,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"featureDiscovery":{"backgroundPattern":{"opacity":{"constant":{"_0":0.25}}}}}"#,
            keyPath: \WhereStylesheet.featureDiscovery.backgroundPattern.opacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"featureDiscovery":{"estimatedTime":{"timelineHeight":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.featureDiscovery.estimatedTime.timelineHeight,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"featureDiscovery":{"estimatedTime":{"timelineSpacing":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.featureDiscovery.estimatedTime.timelineSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"featureDiscovery":{"estimatedTime":{"calculationSpacing":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.featureDiscovery.estimatedTime.calculationSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"featureDiscovery":{"estimatedTime":{"segmentCornerRadius":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.featureDiscovery.estimatedTime.segmentCornerRadius,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"featureDiscovery":{"estimatedTime":{"legendDotSize":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.featureDiscovery.estimatedTime.legendDotSize,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"featureDiscovery":{"widgets":{"lockWidgetHeight":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.featureDiscovery.widgets.lockWidgetHeight,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"featureDiscovery":{"siri":{"card":{"cornerRadius":{"constant":{"_0":42}}}}}}"#,
            keyPath: \WhereStylesheet.featureDiscovery.siri.card.cornerRadius,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"featureDiscovery":{"siri":{"card":{"maxWidth":{"constant":{"_0":42}}}}}}"#,
            keyPath: \WhereStylesheet.featureDiscovery.siri.card.maxWidth,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"featureDiscovery":{"siri":{"card":{"padding":{"constant":{"_0":42}}}}}}"#,
            keyPath: \WhereStylesheet.featureDiscovery.siri.card.padding,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"featureDiscovery":{"siri":{"card":{"spacing":{"constant":{"_0":42}}}}}}"#,
            keyPath: \WhereStylesheet.featureDiscovery.siri.card.spacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"featureDiscovery":{"siri":{"card":{"rowVerticalInset":{"constant":{"_0":42}}}}}}"#,
            keyPath: \WhereStylesheet.featureDiscovery.siri.card.rowVerticalInset,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"featureDiscovery":{"siri":{"bubble":{"cornerRadius":{"constant":{"_0":42}}}}}}"#,
            keyPath: \WhereStylesheet.featureDiscovery.siri.bubble.cornerRadius,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"featureDiscovery":{"siri":{"bubble":{"horizontalPadding":{"constant":{"_0":42}}}}}}"#,
            keyPath: \WhereStylesheet.featureDiscovery.siri.bubble.horizontalPadding,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"featureDiscovery":{"siri":{"bubble":{"verticalPadding":{"constant":{"_0":42}}}}}}"#,
            keyPath: \WhereStylesheet.featureDiscovery.siri.bubble.verticalPadding,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"featureDiscovery":{"siri":{"bubble":{"indent":{"constant":{"_0":42}}}}}}"#,
            keyPath: \WhereStylesheet.featureDiscovery.siri.bubble.indent,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"featureDiscovery":{"siri":{"speakerIcon":{"containerSize":{"constant":{"_0":42}}}}}}"#,
            keyPath: \WhereStylesheet.featureDiscovery.siri.speakerIcon.containerSize,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"featureDiscovery":{"siri":{"speakerIcon":{"symbolPointSize":{"constant":{"_0":42}}}}}}"#,
            keyPath: \WhereStylesheet.featureDiscovery.siri.speakerIcon.symbolPointSize,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"featureDiscovery":{"widgets":{"device":{"cornerRadius":{"constant":{"_0":42}}}}}}"#,
            keyPath: \WhereStylesheet.featureDiscovery.widgets.device.cornerRadius,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"featureDiscovery":{"widgets":{"device":{"contentMaxWidth":{"constant":{"_0":42}}}}}}"#,
            keyPath: \WhereStylesheet.featureDiscovery.widgets.device.contentMaxWidth,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"featureDiscovery":{"widgets":{"device":{"regularContentWidth":{"constant":{"_0":42}}}}}}"#,
            keyPath: \WhereStylesheet.featureDiscovery.widgets.device.regularContentWidth,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"featureDiscovery":{"widgets":{"device":{"padding":{"constant":{"_0":42}}}}}}"#,
            keyPath: \WhereStylesheet.featureDiscovery.widgets.device.padding,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"featureDiscovery":{"widgets":{"device":{"spacing":{"constant":{"_0":42}}}}}}"#,
            keyPath: \WhereStylesheet.featureDiscovery.widgets.device.spacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"featureDiscovery":{"widgets":{"frame":{"cornerRadius":{"constant":{"_0":42}}}}}}"#,
            keyPath: \WhereStylesheet.featureDiscovery.widgets.frame.cornerRadius,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"featureDiscovery":{"widgets":{"frame":{"padding":{"constant":{"_0":42}}}}}}"#,
            keyPath: \WhereStylesheet.featureDiscovery.widgets.frame.padding,
            replacement: 42,
        )
    }
}
