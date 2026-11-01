import Foundation
import Testing
@testable import WhereUI

@MainActor
struct WhereThemeEvidenceStylePatchTests {
    @Test func changesOnlyAuthoredFieldsAfterRoundTrip() throws {
        try verifyThemePatch(
            json: #"{"evidence":{"previewCornerRadius":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.evidence.previewCornerRadius,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"evidence":{"pdfPreviewMinHeight":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.evidence.pdfPreviewMinHeight,
            replacement: 42,
        )
        try verifyThemePatch(
            json: #"{"evidence":{"loadingMinHeight":{"constant":{"_0":42}}}}"#,
            keyPath: \WhereStylesheet.evidence.loadingMinHeight,
            replacement: 42,
        )
    }
}
