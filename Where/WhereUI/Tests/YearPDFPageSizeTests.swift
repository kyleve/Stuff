import Foundation
import Testing
@testable import WhereUI

struct YearPDFPageSizeTests {
    @Test func localeDefaultsAndExplicitMediaBoxes() {
        #expect(YearPDFPageSize.defaultValue(for: Locale(identifier: "en_US")) == .letter)
        #expect(YearPDFPageSize.defaultValue(for: Locale(identifier: "en_CA")) == .letter)
        #expect(YearPDFPageSize.defaultValue(for: Locale(identifier: "en_GB")) == .a4)
        #expect(YearPDFPageSize.letter.portraitBounds.width == 612)
        #expect(YearPDFPageSize.letter.landscapeBounds.width == 792)
        #expect(YearPDFPageSize.a4.portraitBounds.height > YearPDFPageSize.letter.portraitBounds
            .height)
    }
}
