import Foundation
import Testing
@testable import WhereUI

@MainActor
struct WhereThemeSpacingPatchTests {
    @Test func changesOnlyAuthoredFieldsAfterRoundTrip() throws {
        try verifyThemePatch(
            json: #"{"spacing":{"xxSmall":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.spacing.xxSmall,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"spacing":{"xSmall":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.spacing.xSmall,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"spacing":{"small":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.spacing.small,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"spacing":{"medium":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.spacing.medium,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"spacing":{"regular":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.spacing.regular,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"spacing":{"large":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.spacing.large,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"spacing":{"xLarge":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.spacing.xLarge,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"spacing":{"xxLarge":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.spacing.xxLarge,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"spacing":{"xxxLarge":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.spacing.xxxLarge,
            replacement: 42,
        )
    }
}
