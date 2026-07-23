import BroadwayCore
import BroadwayUI
import CoreGraphics
import SwiftUI
import TestHostSupport
import Testing
import UIKit
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

    @Test func regularCardStyle() {
        let card = style.card.regular
        #expect(card.cornerRadius == 28)
        #expect(card.padding == 22)
        #expect(card.contentSpacing == 16)
        #expect(card.progressBarHeight == 10)
        #expect(card.entryStampSize == 88)
        #expect(card.showsArcText)
        #expect(card.regionNameFont == .system(size: 38, weight: .semibold, design: .serif))
        #expect(card.regionNameTracking == -0.5)
        #expect(card.watermarkFontSize == 150)
        #expect(card.watermarkOffset == CGSize(width: 20, height: 12))
        #expect(card.holographicIntensity == 1)
        #expect(card.frameOuterLineWidth == 3.5)
        #expect(card.showsPerforationRing)
        #expect(card.innerFrameInset == 16)
        #expect(card.rosette == .init(
            wobble: 3,
            lineWidth: 3,
            primaryRingSpacing: 18,
            secondaryRingSpacing: 15,
        ))
        #expect(card.glow == .init(opacity: 0.75, radius: 12))
        #expect(card.lift == .init(opacity: 0.6, radius: 34, offsetY: 18))
    }

    @Test func compactCardStyle() {
        let card = style.card.compact
        #expect(card.cornerRadius == 22)
        #expect(card.padding == 16)
        #expect(card.contentSpacing == 10)
        #expect(card.progressBarHeight == 6)
        #expect(card.entryStampSize == 52)
        #expect(!card.showsArcText)
        #expect(card.regionNameTracking == 0)
        #expect(card.watermarkFontSize == 96)
        #expect(card.watermarkOffset == CGSize(width: 12, height: 10))
        #expect(card.holographicIntensity == 0.5)
        #expect(card.frameOuterLineWidth == 2.5)
        #expect(!card.showsPerforationRing)
        #expect(card.innerFrameInset == 12)
        #expect(card.rosette == .init(
            wobble: 2,
            lineWidth: 2,
            primaryRingSpacing: 13,
            secondaryRingSpacing: 11,
        ))
        #expect(card.glow == .init(opacity: 0.55, radius: 6))
        #expect(card.lift == .init(opacity: 0.4, radius: 17, offsetY: 9))
    }

    @Test func cardVariantSubscriptSelectsTheMatchingSpec() {
        #expect(style.card[.regular] == style.card.regular)
        #expect(style.card[.compact] == style.card.compact)
    }

    @Test func sharedCardStyle() {
        let card = style.card
        #expect(card.watermarkOpacity == 0.08)
        #expect(card.glassTintOpacity == 0.18)
        #expect(card.nameOpacity == 0.8)
        #expect(card.rosetteFill == .init(primary: 0.12, secondary: 0.08))
        #expect(card.frame == .init(
            outerOpacity: 0.6,
            thinOpacity: 0.35,
            thinWidth: 1,
            perforationOpacity: 0.45,
            perforationWidth: 2.5,
            perforationDash: [0.01, 6],
            innerOpacity: 0.4,
            innerWidth: 1,
            innerDash: [5, 4],
        ))
    }

    @Test func calendarStyle() {
        let calendar = style.calendar
        #expect(calendar.monthSpacing == 16)
        #expect(calendar.dayMinHeight == 44)
        #expect(calendar.dotSize == 6)
        #expect(calendar.dayDotSize == 8)
        #expect(calendar.dayDotOverlap == 2)
        #expect(calendar.dayDotStrokeWidth == 1.5)
        #expect(calendar.dayNumberDotSpacing == 0)
        #expect(calendar.regionBand.opacity == 0.16)
        #expect(calendar.regionBand.cornerRadius == 14)
        #expect(calendar.regionBand.continuationRadius == 3)
        #expect(calendar.regionBand.verticalInset == 4)
        #expect(calendar.dayContentSpacing == 2)
        #expect(calendar.dayNumberSize == 26)
        #expect(calendar.todayMarker == .accentColor)
        #expect(calendar.todayNumberColor == .white)
        #expect(calendar.unresolvedDayMarker == Color.red.opacity(0.15))
        #expect(calendar.unresolvedNumberColor == .red)
        #expect(calendar.evidenceBadge == .init(
            iconSize: 8,
            padding: 2,
            offset: CGSize(width: 3, height: -2),
        ))

        let month = calendar.month
        #expect(month.sectionSpacing == 8)
        #expect(month.gridSpacing == 6)
        #expect(month.padding == 16)
        #expect(month.cornerRadius == 22)
        #expect(month.currentMonthHighlight == Color.accentColor.opacity(0.08))
        #expect(month.footerDividerSpacing == 8)
        #expect(month.footerSpacing == 4)
        #expect(month.footerRowSpacing == 6)
        #expect(month.unfocusedRowOpacity == 0.55)
    }

    @Test func appIconStyle() {
        let appIcon = style.appIcon
        #expect(appIcon.gridMax == 180)
        #expect(appIcon.previewMax == 280)
        #expect(appIcon.gridSpacing == 20)
        #expect(appIcon.columnSpacing == 16)
        #expect(appIcon.gridPadding == 16)
        #expect(appIcon.cellSpacing == 12)
        #expect(appIcon.cellLabelSpacing == 6)
        #expect(appIcon.backgroundedCellOpacity == 0.5)
        #expect(appIcon.scrim == Color.black.opacity(0.25))

        let panel = appIcon.panel
        #expect(panel.spacing == 14)
        #expect(panel.textSpacing == 4)
        #expect(panel.horizontalPadding == 20)
        #expect(panel.bottomPadding == 16)
        #expect(panel.cornerRadius == 28)
        #expect(panel.background == Color(.systemBackground))
        #expect(panel.shadowColor == Color.black.opacity(0.18))
        #expect(panel.shadowRadius == 18)
        #expect(panel.shadowOffsetY == -4)
        #expect(panel.grabberSize == CGSize(width: 40, height: 5))
        #expect(panel.grabberOpacity == 0.5)
        #expect(panel.grabberTopPadding == 8)
    }

    @Test func timelineStyle() {
        let timeline = style.timeline
        #expect(timeline.rowSpacing == 12)
        #expect(timeline.accentWidth == 4)
        #expect(timeline.accentHeight == 34)
        #expect(timeline.labelSpacing == 2)
        #expect(timeline.trailingMinSpacing == 8)
        #expect(timeline.rowVerticalPadding == 4)
    }

    @Test func regionMapStyle() {
        let regionMap = style.regionMap
        #expect(regionMap.height == 220)
        #expect(regionMap.uncertaintyFillOpacity == 0.15)
        #expect(regionMap.uncertaintyStrokeOpacity == 0.6)
        #expect(regionMap.uncertaintyStrokeWidth == 1)
    }

    @Test func regionPickerStyle() {
        let picker = style.regionPicker
        #expect(picker.mapCornerRadius == 12)
        #expect(picker.selectedFillOpacity == 0.55)
        #expect(picker.unselectedFillOpacity == 0.12)
        #expect(picker.selectedStrokeOpacity == 0.9)
        #expect(picker.unselectedStrokeOpacity == 0.35)
        #expect(picker.selectedStrokeWidth == 2)
        #expect(picker.unselectedStrokeWidth == 1)
        #expect(picker.colorSwatchSize == 40)
        #expect(picker.colorSwatchSelectionRing == 3)
        #expect(picker.colorSwatchMinWidth == 44)
        #expect(picker.glyphTileSize == 48)
        #expect(picker.glyphTileMinWidth == 52)
        #expect(picker.glyphCornerRadius == 6)
        #expect(picker.glyphSelectionStrokeWidth == 2)
        #expect(picker.glyphSelectedBackgroundOpacity == 0.2)
        #expect(picker.mapCenterLatitude == 39.5)
        #expect(picker.mapCenterLongitude == -98.35)
        #expect(picker.mapSpanLatitude == 45)
        #expect(picker.mapSpanLongitude == 55)
    }

    @Test func evidenceStyle() {
        let evidence = style.evidence
        #expect(evidence.previewCornerRadius == 22)
        #expect(evidence.pdfPreviewMinHeight == 420)
        #expect(evidence.loadingMinHeight == 200)
    }

    @Test func elsewhereCardStyle() {
        let card = style.elsewhereCard
        #expect(card.cornerRadius == 22)
        #expect(card.padding == 18)
        #expect(card.iconPointSize == 28)
    }

    @Test func typographyFaces() {
        let typography = style.typography
        #expect(typography.onboardingIcon == .system(size: 72))
        #expect(typography.widgetHeroRegion == .system(.headline, design: .serif).weight(.semibold))
        #expect(typography.widgetTotalNumber == .system(.body, design: .rounded, weight: .bold))
    }

    @Test func motionAnimations() {
        let motion = style.motion
        #expect(motion.reveal == .easeIn(duration: 0.18))
        #expect(motion.reducedReveal == .easeInOut(duration: 0.2))
        #expect(motion.captionFade == .easeOut(duration: 0.3))
    }

    @Test func settingsStyle() {
        let settings = style.settings
        #expect(settings.iconSize == 29)
        #expect(settings.iconCornerRadius == 7)
        #expect(settings.iconSymbolSize == 15)
        #expect(settings.flashAnimation == .easeInOut(duration: 0.4))
        #expect(settings.flashDuration == .seconds(1))
        #expect(settings.scrollSettleDelay == .milliseconds(350))
    }

    @Test func paletteColors() {
        let palette = style.palette
        #expect(palette.primary.backgroundTop == Color(red: 0.07, green: 0.08, blue: 0.13))
        #expect(palette.primary.backgroundBottom == Color(red: 0.02, green: 0.02, blue: 0.05))
        #expect(palette.splash.background == .black)
        #expect(palette.splash.vignetteCenter == Color(white: 0.16))
        #expect(palette.splash.vignetteEdge == .black)
        #expect(palette.splash.iconGlow == .accentColor)
        #expect(palette.splash.caption == .white)
        #expect(palette.splash.captionSecondary == Color.white.opacity(0.7))
        #expect(palette.onboarding.backgroundTop == Color(.systemBackground))
        #expect(palette.onboarding.backgroundBottom == Color.accentColor.opacity(0.12))
    }

    @Test func elementSizes() {
        #expect(style.size.statusIconWidth == 28)
        #expect(style.size.launchIcon == 120)
        #expect(style.size.launchCaptionBottomInset == 72)
    }

    /// With default/system traits the stylesheet resolves to the fixed defaults.
    @MainActor
    @Test func resolvesThroughBroadwayToTheDefaults() throws {
        let context = BContext(traits: .system)
        let resolved = try context.stylesheets.get(WhereStylesheet.self)
        #expect(resolved == .default)
    }

    @MainActor
    @Test func growsDayGridTapTargetAtAccessibilitySizes() throws {
        var context = BContext(traits: .system)
        context.traitOverrides.contentSizeCategory = .accessibilityLarge
        let resolved = try context.stylesheets.get(WhereStylesheet.self)
        #expect(resolved.calendar.dayMinHeight == 56)
    }

    @MainActor
    @Test func flattensCardGlowUnderReduceTransparency() throws {
        var context = BContext(traits: .system)
        context.traitOverrides.accessibility = BAccessibility(isReduceTransparencyEnabled: true)
        let resolved = try context.stylesheets.get(WhereStylesheet.self)
        #expect(resolved.card.regular.glow.radius == 0)
        #expect(resolved.card.compact.glow.radius == 0)
    }
}

/// Covers the WhereUI glue: `EnvironmentValues.stylesheet` resolves a
/// `WhereStylesheet` from the environment's `\.bContext`, falling back to
/// `default` when no context is set.
///
/// The trait-aware resolution itself is covered synchronously by
/// `WhereStylesheetTests` (`growsDayGridTapTargetAtAccessibilitySizes` etc.,
/// resolving directly off a `BContext`), and the `\.bContext` accessor by
/// BroadwayUI's `BContextEnvironmentTests`.
@MainActor
struct WhereStylesheetEnvironmentTests {
    @Test func fallsBackToDefaultWithoutAContext() {
        #expect(EnvironmentValues().stylesheet == .default)
    }

    /// End-to-end, hosted: a Broadway root seeds a trait-overridden context and a
    /// WhereUI view reading `@Environment(\.stylesheet)` (which resolves through
    /// `\.bContext`) sees the accessibility-sized tokens.
    ///
    /// This crosses the WhereUI↔BroadwayUI module boundary at runtime, so it only
    /// resolves when both modules share a single BroadwayUI copy — the reason
    /// `BroadwayCore`/`BroadwayUI` are dynamic libraries. It reproduced the
    /// duplicate-copy failure that only surfaced in the full multi-bundle test
    /// host; guard against a regression.
    @Test func resolvesTraitAwareTokensFromTheBroadwayRoot() throws {
        let box = StylesheetProbeBox()
        let host = UIHostingController(
            rootView: StylesheetProbe(box: box)
                .bContentSizeCategory(.accessibilityLarge)
                .broadwayRoot(),
        )
        try show(host) { _ in
            try waitFor { box.calendarDayMinHeight == 56 }
        }
    }

    /// `whereBroadwayRoot()` — the app/widget entry point — seeds the same
    /// trait-aware context. This is the WhereWidgets extension's only Broadway
    /// root (it has no test bundle of its own), so pin it here.
    @Test func whereBroadwayRootSeedsTraitAwareTokens() throws {
        let box = StylesheetProbeBox()
        let host = UIHostingController(
            rootView: StylesheetProbe(box: box)
                .bContentSizeCategory(.accessibilityLarge)
                .whereBroadwayRoot(),
        )
        try show(host) { _ in
            try waitFor { box.calendarDayMinHeight == 56 }
        }
    }
}

private final class StylesheetProbeBox {
    var calendarDayMinHeight: CGFloat?
}

private struct StylesheetProbe: View {
    let box: StylesheetProbeBox

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        Color.clear
            .onChange(of: stylesheet.calendar.dayMinHeight, initial: true) { _, newValue in
                box.calendarDayMinHeight = newValue
            }
    }
}
