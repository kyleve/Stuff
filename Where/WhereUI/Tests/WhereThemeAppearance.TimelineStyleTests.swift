import Foundation
import Testing
@testable import WhereUI

@MainActor
struct WhereThemeTimelineStylePatchTests {
    @Test func changesOnlyAuthoredFieldsAfterRoundTrip() throws {
        try verifyThemePatch(
            json: #"{"timeline":{"flight":{"verticalPadding":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.timeline.flight.verticalPadding,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"timeline":{"flight":{"labelSpacing":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.timeline.flight.labelSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"timeline":{"overview":{"spacing":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.timeline.overview.spacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"timeline":{"overview":{"padding":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.timeline.overview.padding,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"timeline":{"overview":{"cornerRadius":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.timeline.overview.cornerRadius,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"timeline":{"overview":{"borderWidth":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.timeline.overview.borderWidth,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"timeline":{"overview":{"pinsToViewport":{"constant":{"_0":false}}}}}"#,
            keyPath: \WhereStylesheet.timeline.overview.pinsToViewport,
            replacement: false,
        )
        try verifyThemePatch(
            json: #"{"timeline":{"ribbon":{"monthLabelSpacing":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.timeline.ribbon.monthLabelSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"timeline":{"ribbon":{"height":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.timeline.ribbon.height,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"timeline":{"ribbon":{"borderWidth":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.timeline.ribbon.borderWidth,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"timeline":{"ribbon":{"regionSpacing":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.timeline.ribbon.regionSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"timeline":{"ribbon":{"regionLabelSpacing":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.timeline.ribbon.regionLabelSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"timeline":{"ribbon":{"separatesRegions":{"constant":{"_0":false}}}}}"#,
            keyPath: \WhereStylesheet.timeline.ribbon.separatesRegions,
            replacement: false,
        )
        try verifyThemePatch(
            json: #"{"timeline":{"rail":{"lineWidth":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.timeline.rail.lineWidth,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"timeline":{"rail":{"toCardSpacing":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.timeline.rail.toCardSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"timeline":{"rail":{"nodeSize":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.timeline.rail.nodeSize,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"timeline":{"rail":{"nodeFillOpacity":{"constant":{"_0":0.25}}}}}"#,
            keyPath: \WhereStylesheet.timeline.rail.nodeFillOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"timeline":{"rail":{"nodeStrokeWidth":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.timeline.rail.nodeStrokeWidth,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"timeline":{"row":{"spacing":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.timeline.row.spacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"timeline":{"row":{"labelSpacing":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.timeline.row.labelSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"timeline":{"row":{"gap":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.timeline.row.gap,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"timeline":{"row":{"baseHeight":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.timeline.row.baseHeight,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"timeline":{"row":{"yearScaleHeight":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.timeline.row.yearScaleHeight,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"timeline":{"row":{"horizontalPadding":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.timeline.row.horizontalPadding,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"timeline":{"row":{"verticalPadding":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.timeline.row.verticalPadding,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"timeline":{"row":{"cornerRadius":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.timeline.row.cornerRadius,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"timeline":{"row":{"fillOpacity":{"constant":{"_0":0.25}}}}}"#,
            keyPath: \WhereStylesheet.timeline.row.fillOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"timeline":{"row":{"borderOpacity":{"constant":{"_0":0.25}}}}}"#,
            keyPath: \WhereStylesheet.timeline.row.borderOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"timeline":{"row":{"borderWidth":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.timeline.row.borderWidth,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"timeline":{"row":{"countHorizontalPadding":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.timeline.row.countHorizontalPadding,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"timeline":{"row":{"countVerticalPadding":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.timeline.row.countVerticalPadding,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"timeline":{"row":{"countFillOpacity":{"constant":{"_0":0.25}}}}}"#,
            keyPath: \WhereStylesheet.timeline.row.countFillOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"timeline":{"row":{"stacksDayCount":{"constant":{"_0":false}}}}}"#,
            keyPath: \WhereStylesheet.timeline.row.stacksDayCount,
            replacement: false,
        )
        try verifyThemePatch(
            json: #"{"timeline":{"planned":{"fillOpacity":{"constant":{"_0":0.25}}}}}"#,
            keyPath: \WhereStylesheet.timeline.planned.fillOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"timeline":{"planned":{"borderOpacity":{"constant":{"_0":0.25}}}}}"#,
            keyPath: \WhereStylesheet.timeline.planned.borderOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"timeline":{"planned":{"hatchOpacity":{"constant":{"_0":0.25}}}}}"#,
            keyPath: \WhereStylesheet.timeline.planned.hatchOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"timeline":{"planned":{"hatchSpacing":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.timeline.planned.hatchSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"timeline":{"planned":{"hatchLineWidth":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.timeline.planned.hatchLineWidth,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"timeline":{"planned":{"labelOpacity":{"constant":{"_0":0.25}}}}}"#,
            keyPath: \WhereStylesheet.timeline.planned.labelOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"timeline":{"planned":{"transitionHeight":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.timeline.planned.transitionHeight,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"timeline":{"planned":{"joinedBaseHeight":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.timeline.planned.joinedBaseHeight,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"timeline":{"planned":{"joinedVerticalPadding":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.timeline.planned.joinedVerticalPadding,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"timeline":{"planned":{"joinedLabelSpacing":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.timeline.planned.joinedLabelSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"timeline":{"planned":{"joinedCountHorizontalPadding":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.timeline.planned.joinedCountHorizontalPadding,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"timeline":{"planned":{"joinedCountVerticalPadding":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.timeline.planned.joinedCountVerticalPadding,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"timeline":{"row":{"singleDay":{"baseHeight":{"constant":{"_0":42}}}}}}"#,
            keyPath: \WhereStylesheet.timeline.row.singleDay.baseHeight,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"timeline":{"row":{"singleDay":{"verticalPadding":{"constant":{"_0":42}}}}}}"#,
            keyPath: \WhereStylesheet.timeline.row.singleDay.verticalPadding,
            replacement: 42,
        )
    }
}
