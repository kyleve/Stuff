import Foundation
import SwiftUI
import Testing
import ViewDocumentCore
import ViewDocumentUI
@testable import WhereUI

@MainActor
struct WhereThemeTypographyPatchTests {
    @Test func semanticFontOverridePreservesUnrelatedFaces() throws {
        let font = ViewFontDescriptor(size: .semantic(.body), weight: .bold, design: .serif)
        try verifyThemePatch(
            json: #"{"typography":{"widgetHeroRegion":{"constant":{"_0":{"size":{"semantic":{"_0":"body"}},"weight":"bold","design":"serif"}}}}}"#,
            keyPath: \WhereStylesheet.typography.widgetHeroRegion,
            replacement: font.font,
        )
    }
}
