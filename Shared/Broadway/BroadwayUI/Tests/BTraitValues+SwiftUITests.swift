import BroadwayCore
@testable import BroadwayUI
import SwiftUI
import Testing

struct BModeSwiftUIMappingTests {
    @Test("ColorScheme maps to BMode")
    func mapsColorScheme() {
        #expect(BMode(.dark) == .dark)
        #expect(BMode(.light) == .light)
    }
}

struct BContentSizeCategorySwiftUIMappingTests {
    @Test("DynamicTypeSize maps to the matching BContentSizeCategory")
    func mapsDynamicTypeSize() {
        #expect(BContentSizeCategory(.xSmall) == .extraSmall)
        #expect(BContentSizeCategory(.small) == .small)
        #expect(BContentSizeCategory(.medium) == .medium)
        #expect(BContentSizeCategory(.large) == .large)
        #expect(BContentSizeCategory(.xLarge) == .extraLarge)
        #expect(BContentSizeCategory(.xxLarge) == .extraExtraLarge)
        #expect(BContentSizeCategory(.xxxLarge) == .extraExtraExtraLarge)
        #expect(BContentSizeCategory(.accessibility1) == .accessibilityMedium)
        #expect(BContentSizeCategory(.accessibility2) == .accessibilityLarge)
        #expect(BContentSizeCategory(.accessibility3) == .accessibilityExtraLarge)
        #expect(BContentSizeCategory(.accessibility4) == .accessibilityExtraExtraLarge)
        #expect(BContentSizeCategory(.accessibility5) == .accessibilityExtraExtraExtraLarge)
    }
}
