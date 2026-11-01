import Foundation
import Testing
@testable import WhereUI

@MainActor
struct WhereThemePassportSealStylePatchTests {
    @Test func changesOnlyAuthoredFieldsAfterRoundTrip() throws {
        try verifyThemePatch(
            json: #"{"passportSeal":{"size":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.passportSeal.size,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"passportSeal":{"rotationDegrees":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.passportSeal.rotationDegrees,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"passportSeal":{"outerLineWidth":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.passportSeal.outerLineWidth,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"passportSeal":{"innerLineWidth":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.passportSeal.innerLineWidth,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"passportSeal":{"innerInset":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.passportSeal.innerInset,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"passportSeal":{"dashLength":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.passportSeal.dashLength,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"passportSeal":{"dashSpacing":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.passportSeal.dashSpacing,
            replacement: 42,
        )
    }
}
