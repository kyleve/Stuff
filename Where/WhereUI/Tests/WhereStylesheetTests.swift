import BroadwayCore
import CoreGraphics
import Testing
@testable import WhereUI

/// `WhereStylesheet` currently ships the fixed geometry migrated from the former
/// `UIConstants`. These assertions pin those values so the migration — and any
/// later trait-aware derivation — can't silently drift the defaults.
struct WhereStylesheetTests {
    private let style = WhereStylesheet.default

    @Test func spacingScale() {
        #expect(style.spacing.xxSmall == 2)
        #expect(style.spacing.xSmall == 4)
        #expect(style.spacing.small == 6)
        #expect(style.spacing.medium == 8)
        #expect(style.spacing.regular == 10)
        #expect(style.spacing.large == 12)
        #expect(style.spacing.xLarge == 14)
        #expect(style.spacing.xxLarge == 16)
        #expect(style.spacing.xxxLarge == 20)
    }

    @Test func cardPaddingAndCornerRadii() {
        #expect(style.padding.compactCard == 16)
        #expect(style.padding.card == 22)
        #expect(style.cornerRadius.compactCard == 22)
        #expect(style.cornerRadius.card == 28)
    }

    @Test func cardShadowGeometry() {
        #expect(style.shadow.cardRadius == 34)
        #expect(style.shadow.cardRadiusCompact == 17)
        #expect(style.shadow.cardGlowRadius == 12)
        #expect(style.shadow.cardGlowRadiusCompact == 6)
        #expect(style.shadow.cardOffsetY == 18)
        #expect(style.shadow.cardOffsetYCompact == 9)
    }

    @Test func elementSizes() {
        #expect(style.size.progressBarHeight == 10)
        #expect(style.size.progressBarHeightCompact == 6)
        #expect(style.size.timelineAccentWidth == 4)
        #expect(style.size.timelineAccentHeight == 34)
        #expect(style.size.calendarDot == 6)
        #expect(style.size.calendarDayMinHeight == 44)
        #expect(style.size.heroNumberFontSize == 40)
        #expect(style.size.regionNameFontSize == 38)
        #expect(style.size.statusIconWidth == 28)
        #expect(style.size.entryStamp == 88)
        #expect(style.size.entryStampCompact == 52)
        #expect(style.size.stampWatermark == 150)
        #expect(style.size.stampWatermarkCompact == 96)
        #expect(style.size.regionMapHeight == 220)
        #expect(style.size.appIconGridMax == 180)
        #expect(style.size.appIconPreviewLargeMax == 280)
        #expect(style.size.launchIcon == 120)
        #expect(style.size.launchCaptionBottomInset == 72)
    }

    /// The stylesheet resolves through Broadway's cache and, for now, produces
    /// the fixed defaults regardless of the context's traits.
    @MainActor
    @Test func resolvesThroughBroadwayToTheDefaults() throws {
        let context = BContext(traits: .system)
        let resolved = try context.stylesheets.get(WhereStylesheet.self)
        #expect(resolved == .default)
    }
}
