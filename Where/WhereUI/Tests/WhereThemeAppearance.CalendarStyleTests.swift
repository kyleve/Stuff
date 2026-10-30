import Foundation
import Testing
@testable import WhereUI

@MainActor
struct WhereThemeCalendarStylePatchTests {
    @Test func changesOnlyAuthoredFieldsAfterRoundTrip() throws {
        try verifyThemePatch(
            json: #"{"calendar":{"monthSpacing":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.calendar.monthSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"calendar":{"dotSize":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.calendar.dotSize,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"calendar":{"month":{"sectionSpacing":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.calendar.month.sectionSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"calendar":{"month":{"gridSpacing":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.calendar.month.gridSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"calendar":{"month":{"weekdayFontSize":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.calendar.month.weekdayFontSize,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"calendar":{"month":{"padding":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.calendar.month.padding,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"calendar":{"month":{"cornerRadius":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.calendar.month.cornerRadius,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"calendar":{"month":{"footerDividerSpacing":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.calendar.month.footerDividerSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"calendar":{"month":{"footerSpacing":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.calendar.month.footerSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"calendar":{"month":{"footerRowSpacing":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.calendar.month.footerRowSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"calendar":{"month":{"stacksFooter":{"constant":{"_0":false}}}}}"#,
            keyPath: \WhereStylesheet.calendar.month.stacksFooter,
            replacement: false,
        )
        try verifyThemePatch(
            json: #"{"calendar":{"month":{"unfocusedRowOpacity":{"constant":{"_0":0.25}}}}}"#,
            keyPath: \WhereStylesheet.calendar.month.unfocusedRowOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"calendar":{"regionBand":{"opacity":{"constant":{"_0":0.25}}}}}"#,
            keyPath: \WhereStylesheet.calendar.regionBand.opacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"calendar":{"regionBand":{"cornerRadius":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.calendar.regionBand.cornerRadius,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"calendar":{"regionBand":{"continuationRadius":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.calendar.regionBand.continuationRadius,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"calendar":{"regionBand":{"verticalInset":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.calendar.regionBand.verticalInset,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"calendar":{"day":{"minHeight":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.calendar.day.minHeight,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"calendar":{"day":{"numberSize":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.calendar.day.numberSize,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"calendar":{"day":{"numberFontSize":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.calendar.day.numberFontSize,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"calendar":{"day":{"numberDotSpacing":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.calendar.day.numberDotSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"calendar":{"day":{"dotSize":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.calendar.day.dotSize,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"calendar":{"day":{"dotOverlap":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.calendar.day.dotOverlap,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"calendar":{"day":{"dotStrokeWidth":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.calendar.day.dotStrokeWidth,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"calendar":{"day":{"contentSpacing":{"constant":{"_0":42}}}}}"#,
            keyPath: \WhereStylesheet.calendar.day.contentSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"calendar":{"month":{"plain":{"borderWidth":{"constant":{"_0":42}}}}}}"#,
            keyPath: \WhereStylesheet.calendar.month.plain.borderWidth,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"calendar":{"regionBand":{"planned":{"fillOpacity":{"constant":{"_0":0.25}}}}}}"#,
            keyPath: \WhereStylesheet.calendar.regionBand.planned.fillOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"calendar":{"regionBand":{"planned":{"hatchOpacity":{"constant":{"_0":0.25}}}}}}"#,
            keyPath: \WhereStylesheet.calendar.regionBand.planned.hatchOpacity,
            replacement: 0.25,
        )
        try verifyThemePatch(
            json: #"{"calendar":{"regionBand":{"planned":{"hatchSpacing":{"constant":{"_0":42}}}}}}"#,
            keyPath: \WhereStylesheet.calendar.regionBand.planned.hatchSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"calendar":{"regionBand":{"planned":{"hatchLineWidth":{"constant":{"_0":42}}}}}}"#,
            keyPath: \WhereStylesheet.calendar.regionBand.planned.hatchLineWidth,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"calendar":{"day":{"badge":{"iconSize":{"constant":{"_0":42}}}}}}"#,
            keyPath: \WhereStylesheet.calendar.day.badge.iconSize,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"calendar":{"day":{"badge":{"iconSpacing":{"constant":{"_0":42}}}}}}"#,
            keyPath: \WhereStylesheet.calendar.day.badge.iconSpacing,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"calendar":{"day":{"badge":{"padding":{"constant":{"_0":42}}}}}}"#,
            keyPath: \WhereStylesheet.calendar.day.badge.padding,
            replacement: 42,
        )
    }
}
