import BroadwayCore
import BroadwayUI
import CoreGraphics
import SwiftUI
import TestHostSupport
import Testing
import UIKit
import WhereCore
@testable import WhereUI

/// `WhereStylesheet` currently ships the fixed geometry migrated from the former
/// `UIConstants`. These assertions pin those values so the migration — and any
/// later trait-aware derivation — can't silently drift the defaults.
struct WhereStylesheetTests {
    private let style = WhereStylesheet.default

    @MainActor
    @Test func themesRetainDistinctIdentityWithEquivalentTokens() throws {
        var standardThemes = BThemes()
        standardThemes[WhereTheme.self] = .standard
        var alternateThemes = BThemes()
        alternateThemes[WhereTheme.self] = .alternate

        let standardContext = BContext(traits: .system, themes: standardThemes)
        let alternateContext = BContext(traits: .system, themes: alternateThemes)
        let standard = try standardContext.stylesheets.get(WhereStylesheet.self)
        let alternate = try alternateContext.stylesheets.get(WhereStylesheet.self)

        #expect(standard.theme == .standard)
        #expect(alternate.theme == .alternate)
        var normalizedStandard = standard
        normalizedStandard.theme = WhereTheme.alternate
        #expect(normalizedStandard == alternate)
    }

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

    @Test func locationWelcomeStyle() {
        let welcome = style.locationWelcome
        #expect(welcome.maxWidth == 390)
        #expect(welcome.cornerRadius == 30)
        #expect(welcome.padding == 24)
        #expect(welcome.contentSpacing == 16)
        #expect(welcome.paperOpacity == 0.92)
        #expect(welcome.scrimOpacity == 0.28)
        #expect(welcome.glassTintOpacity == 0.2)
        #expect(welcome.outlineOpacity == 0.28)
        #expect(welcome.outlineWidth == 1)
        #expect(welcome.inset == 9)
        #expect(welcome.insetDashLength == 5)
        #expect(welcome.insetDashSpacing == 4)
        #expect(welcome.shadowOpacity == 0.42)
        #expect(welcome.shadowRadius == 30)
        #expect(welcome.shadowOffsetY == 16)
        #expect(welcome.close.offset == CGSize(width: 8, height: -8))
        #expect(welcome.close.tintOpacity == 0.24)
        #expect(welcome.close.outlineOpacity == 0.38)
        #expect(welcome.close.glow == .init(opacity: 0.28, radius: 8))
        #expect(welcome.close.lift == .init(opacity: 0.22, radius: 5, offsetY: 3))
        #expect(welcome.motion == .standard)
    }

    @Test func regularCardStyle() {
        let card = style.card.regular
        #expect(style.card.estimatedProgressOpacity == 0.3)
        #expect(card.cornerRadius == 28)
        #expect(card.padding == 22)
        #expect(card.contentSpacing == 16)
        #expect(card.progressBarHeight == 10)
        #expect(card.entryStamp == expectedEntryStamp(size: 88, showsArcText: true))
        #expect(card.regionNameTypography == .init(
            size: .fixed(38),
            weight: .semibold,
            design: .serif,
        ))
        #expect(card.regionNameTypography.font == .system(
            size: 38,
            weight: .semibold,
            design: .serif,
        ))
        #expect(card.heroNumberTypography == .init(
            size: .fixed(40),
            weight: .bold,
            design: .rounded,
        ))
        #expect(card.dayUnitTypography == .init(
            size: .semantic(.title3),
            weight: .medium,
            design: .default,
        ))
        #expect(card.regionNameTracking == -0.5)
        #expect(card.watermarkFontSize == 150)
        #expect(card.watermarkOffset == CGSize(width: 20, height: 12))
        #expect(card.regionShape == .init(
            watermark: .init(
                center: CGPoint(x: 0.7, y: 0.57),
                extent: CGSize(width: 0.72, height: 0.78),
                scale: 0.88,
                fillOpacity: 0.13,
                stroke: .init(opacity: 0.28, width: 1.5),
            ),
            stamp: .init(
                center: CGPoint(x: 0.5, y: 0.5),
                extent: CGSize(width: 0.78, height: 0.78),
                scale: 0.88,
                fillOpacity: 0.78,
                stroke: nil,
            ),
            securityBorder: .init(
                inset: 9,
                glyphSize: 8,
                spacing: 11,
                opacity: 0.22,
            ),
        ))
        #expect(card.sheen == .init(
            intensity: 1,
            staticGlintIntensity: 0.25,
            staticPose: .init(roll: 0, pitch: -1),
        ))
        #expect(card.rosette == .init(
            wobble: 2,
            lineWidth: 1,
            primaryRingSpacing: 13.5,
            secondaryRingSpacing: 9.5,
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
        #expect(card.entryStamp == expectedEntryStamp(size: 52, showsArcText: false))
        #expect(card.regionNameTypography == .init(
            size: .semantic(.title3),
            weight: .semibold,
            design: .serif,
        ))
        #expect(card.heroNumberTypography == .init(
            size: .semantic(.title),
            weight: .bold,
            design: .rounded,
        ))
        #expect(card.dayUnitTypography == .init(
            size: .semantic(.subheadline),
            weight: .medium,
            design: .default,
        ))
        #expect(card.regionNameTracking == 0)
        #expect(card.watermarkFontSize == 96)
        #expect(card.watermarkOffset == CGSize(width: 12, height: 10))
        #expect(card.regionShape == nil)
        #expect(card.sheen == .init(
            intensity: 0.5,
            staticGlintIntensity: 0.5,
            staticPose: .init(roll: 0, pitch: 0),
        ))
        #expect(card.rosette == .init(
            wobble: 2,
            lineWidth: 1,
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

    private func expectedEntryStamp(
        size: CGFloat,
        showsArcText: Bool,
    ) -> WhereStylesheet.CardStyle.EntryStamp {
        .init(
            size: size,
            outerRing: .init(opacity: 0.7, lineWidthFraction: 0.035),
            innerRing: .init(
                opacity: 0.45,
                lineWidthFraction: 0.012,
                dash: .init(lengthFraction: 0.05, spacingFraction: 0.035),
                insetFraction: 0.13,
            ),
            content: .init(
                spacingFraction: 0.02,
                artworkExtent: CGSize(width: 0.42, height: 0.28),
                symbolFont: .init(sizeFraction: 0.26, weight: .regular, design: .default),
                yearFont: .init(sizeFraction: 0.15, weight: .bold, design: .serif),
                opacity: 0.85,
            ),
            arc: showsArcText ? .init(
                radiusFraction: 0.37,
                font: .init(sizeFraction: 0.1, weight: .semibold, design: .serif),
                opacity: 0.7,
                maximumSweepDegrees: 250,
                sweepDegreesPerCharacter: 17,
            ) : nil,
            rotationDegrees: -8,
        )
    }

    @Test func sharedCardStyle() {
        let card = style.card
        #expect(card.watermarkOpacity == 0.08)
        #expect(card.glassTintOpacity == 0.18)
        #expect(card.nameOpacity == 0.8)
        #expect(card.rosetteFill == .init(primary: 0.12, secondary: 0.08))
        #expect(card.securityPrint == .standard)
        #expect(card.securityPrint.backgroundBlendMode == .normal)
        #expect(card.securityPrint.tint(.red) == .red)
        #expect(card.dayCount == .standard)
        #expect(card.dayCount.revealDelay == .milliseconds(500))
        #expect(card.dayCount.animation == .easeOut(duration: 0.3))
        #expect(card.estimateSticker == .standard)
        #expect(card.estimateSticker.contentOpacity == 0.92)
        #expect(card.estimateSticker.scale == 0.8)
        #expect(card.constellation == .init(
            gridResolution: 48,
            maximumPointCount: 96,
            coreDiameter: 2.5,
            coreOpacity: 0.92,
            coreWhiteMix: 0.72,
            haloRadius: 6,
            haloOpacity: 0.32,
        ))
    }

    @Test func locationCardOvertakeMotion() {
        let motion = style.locationCardStack.overtake
        #expect(motion == .standard)
        #expect(motion.duration == 0.72)
        #expect(motion.bounce == 0.18)
        #expect(motion.lateralArc == 18)
        #expect(motion.liftScale == 1.03)
        #expect(motion.rotationDegrees == 1.5)
        #expect(motion.settleScale == 0.975)
        #expect(motion.minimumOpacity == 1)
        #expect(motion.usesSpatialMotion)
        #expect(WhereStylesheet.LocationCardStackStyle.OvertakeMotion.durationRange == 0.3 ... 1.2)
        #expect(WhereStylesheet.LocationCardStackStyle.OvertakeMotion.bounceRange == 0 ... 0.5)
        #expect(WhereStylesheet.LocationCardStackStyle.OvertakeMotion.lateralArcRange == 0 ... 48)
        #expect(WhereStylesheet.LocationCardStackStyle.OvertakeMotion.liftScaleRange == 1 ... 1.08)
        #expect(WhereStylesheet.LocationCardStackStyle.OvertakeMotion.rotationRange == 0 ... 6)
        #expect(WhereStylesheet.LocationCardStackStyle.OvertakeMotion
            .settleScaleRange == 0.92 ... 1)
    }

    /// The roll carries the count so it knows which way to spin the digits; the
    /// Reduce-Motion pairing drops the roll for a fade and ignores the count.
    @Test func dayCountTransitions() {
        let rolling = WhereStylesheet.CardStyles.DayCountStyle.standard
        #expect(rolling.morph == .rollingDigits)
        #expect(rolling.transition(days: 148) == .numericText(value: 148))
        #expect(rolling.transition(days: 149) != rolling.transition(days: 148))

        let reduced = WhereStylesheet.CardStyles.DayCountStyle.reducedMotion
        #expect(reduced.revealDelay == .milliseconds(500))
        #expect(reduced.morph == .crossFade)
        #expect(reduced.transition(days: 148) == .opacity)
        #expect(reduced.transition(days: 149) == reduced.transition(days: 148))
        #expect(reduced.animation == .easeInOut(duration: 0.2))
    }

    @Test func calendarStyle() {
        let calendar = style.calendar
        #expect(calendar.monthSpacing == 16)
        #expect(calendar.dotSize == 6)
        #expect(calendar.regionBand.opacity == 0.16)
        #expect(calendar.regionBand.cornerRadius == 14)
        #expect(calendar.regionBand.continuationRadius == 3)
        #expect(calendar.regionBand.verticalInset == 4)
        #expect(calendar.regionBand.planned == .init(
            fillOpacity: 0.07,
            hatchOpacity: 0.32,
            hatchSpacing: 6,
            hatchLineWidth: 1,
        ))

        let day = calendar.day
        #expect(day.minHeight == 44)
        #expect(day.numberSize == 26)
        #expect(day.numberDotSpacing == 0)
        #expect(day.dotSize == 8)
        #expect(day.dotOverlap == 2)
        #expect(day.dotStrokeWidth == 1.5)
        #expect(day.contentSpacing == 2)
        #expect(day.todayMarker == .accentColor)
        #expect(day.todayNumberColor == .white)
        #expect(day.unresolvedMarker == Color.red.opacity(0.15))
        #expect(day.unresolvedNumberColor == .red)
        #expect(day.evidenceBadge == .init(
            iconSize: 8,
            padding: 2,
            offset: CGSize(width: 3, height: -2),
        ))

        let month = calendar.month
        #expect(month.sectionSpacing == 8)
        #expect(month.gridSpacing == 6)
        #expect(month.padding == 16)
        #expect(month.cornerRadius == 28)
        #expect(month.plain.fill == Color.primary.opacity(0.03))
        #expect(month.plain.border == Color.primary.opacity(0.12))
        #expect(month.plain.borderWidth == 2)
        #expect(month.plain.foreground == .primary)
        #expect(month.current.fill == Color.accentColor.opacity(0.08))
        #expect(month.current.border == Color.accentColor.opacity(0.7))
        #expect(month.current.borderWidth == 3)
        #expect(month.current.foreground == Color.primary.mix(
            with: .accentColor,
            by: 0.25,
            in: .perceptual,
        ))
        #expect(month.footerDividerSpacing == 8)
        #expect(month.footerSpacing == 4)
        #expect(month.footerRowSpacing == 6)
        #expect(month.unfocusedRowOpacity == 0.55)
    }

    @Test func locationForecastStyle() {
        let forecast = style.locationForecast
        #expect(forecast.cornerRadius == 22)
        #expect(forecast.padding == 16)
        #expect(forecast.rowSpacing == 12)
        #expect(forecast.expansionAnimation == .easeInOut(duration: 0.2))
        #expect(forecast.surface == .init(
            outlineWidth: 1.25,
            inset: 9,
            microprintGlyphSize: 7,
            microprintSpacing: 10,
            rosetteWobble: 5,
            rosetteLineWidth: 0.75,
            primaryRingSpacing: 10,
            secondaryRingSpacing: 16,
            shadowColor: Color.black.opacity(0.08),
            shadowRadius: 10,
            shadowOffsetY: 3,
        ))
        #expect(forecast.header == .init(
            contentSpacing: 10,
            textSpacing: 2,
            titleFont: .system(.headline, design: .serif),
            elapsedFont: .footnote,
            minimumHeight: 50,
        ))
        #expect(forecast.row == .init(
            cornerRadius: 14,
            padding: 10,
            contentSpacing: 6,
            estimateSpacing: 2,
            regionFont: .system(.title3, design: .serif),
            estimateFont: .system(.headline, design: .rounded),
            detailFont: .footnote,
            outlineWidth: 0.75,
        ))
        #expect(forecast.progress == .init(
            height: 8,
            hatchSpacing: 6,
            hatchLineWidth: 1,
        ))
        #expect(forecast.controls == .init(
            sectionSpacing: 8,
            layoutSpacing: 6,
            cornerRadius: 12,
            horizontalPadding: 10,
            minimumHeight: 44,
            strokeWidth: 1,
            font: .subheadline,
        ))
        #expect(forecast.ink == .standard)
        #expect(forecast.ink.microprintOpacity == 0.18)
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
        let overview = timeline.overview
        #expect(overview.spacing == 12)
        #expect(overview.padding == 16)
        #expect(overview.cornerRadius == 24)
        #expect(overview.background == Color.primary.opacity(0.035))
        #expect(overview.border == Color.primary.opacity(0.1))
        #expect(overview.borderWidth == 1)
        #expect(overview.yearFont == .system(.title2, design: .serif).bold())
        #expect(overview.pinsToViewport)

        let ribbon = timeline.ribbon
        #expect(ribbon.monthLabelSpacing == 6)
        #expect(ribbon.height == 18)
        #expect(ribbon.track == Color.primary.opacity(0.07))
        #expect(ribbon.border == Color.primary.opacity(0.12))
        #expect(ribbon.borderWidth == 1)
        #expect(ribbon.regionSpacing == 8)
        #expect(ribbon.regionLabelSpacing == 4)
        #expect(ribbon.separatesRegions == false)

        let rail = timeline.rail
        #expect(rail.lineWidth == 4)
        #expect(rail.toCardSpacing == 10)
        #expect(rail.nodeSize == 42)
        #expect(rail.nodeEmojiFont == .system(size: 20))
        #expect(rail.nodeFillOpacity == 0.18)
        #expect(rail.nodeStrokeWidth == 2)

        let row = timeline.row
        #expect(row.spacing == 12)
        #expect(row.labelSpacing == 3)
        #expect(row.gap == 8)
        #expect(row.baseHeight == 64)
        #expect(row.yearScaleHeight == 320)
        #expect(row.horizontalPadding == 14)
        #expect(row.verticalPadding == 12)
        #expect(row.cornerRadius == 18)
        #expect(row.fillOpacity == 0.09)
        #expect(row.borderOpacity == 0.24)
        #expect(row.borderWidth == 1)
        #expect(row.countHorizontalPadding == 10)
        #expect(row.countVerticalPadding == 6)
        #expect(row.countFillOpacity == 0.16)
        #expect(row.stacksDayCount == false)

        let planned = timeline.planned
        #expect(planned.fillOpacity == 0.035)
        #expect(planned.borderOpacity == 0.14)
        #expect(planned.hatchOpacity == 0.16)
        #expect(planned.hatchSpacing == 8)
        #expect(planned.hatchLineWidth == 1)
        #expect(planned.labelOpacity == 0.7)
        #expect(planned.transitionHeight == 16)
        #expect(planned.joinedBaseHeight == 32)
        #expect(planned.joinedVerticalPadding == 8)
        #expect(planned.joinedLabelSpacing == 5)
        #expect(planned.joinedCountHorizontalPadding == 8)
        #expect(planned.joinedCountVerticalPadding == 4)
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
        #expect(motion.reveal == .easeIn(duration: 0.16))
        #expect(motion.reducedReveal == .easeInOut(duration: 0.2))
        #expect(motion.captionFade == .easeOut(duration: 0.3))
        #expect(motion.staggeredReveal.animation == .easeOut(duration: 0.35))
        #expect(motion.staggeredReveal.verticalOffset == 16)
        #expect(motion.staggeredReveal.delay == 0.08)

        let hidden = motion.staggeredReveal.presentation(
            isRevealed: false,
            motionIsStatic: false,
            order: 2,
        )
        #expect(hidden.opacity == 0)
        #expect(hidden.verticalOffset == 16)
        #expect(hidden.animation == .easeOut(duration: 0.35).delay(0.16))

        let staticPresentation = motion.staggeredReveal.presentation(
            isRevealed: false,
            motionIsStatic: true,
            order: 2,
        )
        #expect(staticPresentation == .visible)
    }

    @Test func launchTimings() {
        let launch = style.launch
        #expect(launch.minimumSplashDuration == .milliseconds(800))
        #expect(launch.captionDelay == .milliseconds(1200))
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

    @Test func featureDiscoveryStyle() {
        let featureDiscovery = style.featureDiscovery
        #expect(featureDiscovery.marketingHeader == .init(
            badgeSize: 76,
            symbolPointSize: 34,
            badgeTintOpacity: 0.14,
            contentMaxWidth: 560,
            spacing: 14,
            verticalPadding: 24,
        ))
        #expect(featureDiscovery.marketingPanel == .init(
            cornerRadius: 20,
            maxWidth: 680,
            padding: 16,
            contentSpacing: 12,
            rowVerticalInset: 6,
        ))
        #expect(featureDiscovery.backgroundPattern == .init(
            contourSpacing: 30,
            primaryDistortion: 13,
            secondaryDistortion: 6,
            horizontalScale: 1.22,
            centerXRatio: 0.18,
            centerYRatio: 0.46,
            phaseStep: 0.31,
            lineWidth: 0.9,
            opacity: 0.12,
        ))
        #expect(featureDiscovery.estimatedTime == .init(
            timelineHeight: 18,
            timelineSpacing: 3,
            calculationSpacing: 8,
            segmentCornerRadius: 5,
            legendDotSize: 10,
        ))
        #expect(featureDiscovery.siri == .init(
            card: .init(
                cornerRadius: 20,
                maxWidth: 680,
                padding: 16,
                spacing: 12,
                rowVerticalInset: 6,
            ),
            bubble: .init(
                cornerRadius: 16,
                horizontalPadding: 12,
                verticalPadding: 10,
                indent: 34,
            ),
            speakerIcon: .init(containerSize: 28, symbolPointSize: 12),
            accent: Color(white: 0.28),
        ))
        #expect(featureDiscovery.widgets == .init(
            device: .init(
                cornerRadius: 28,
                contentMaxWidth: 560,
                regularContentWidth: 320,
                dynamicTypeLimit: .xLarge,
                padding: 14,
                spacing: 12,
            ),
            frame: .init(cornerRadius: 18, padding: 12),
            wallpapers: .init(
                home: .init(top: .indigo, bottom: .cyan),
                lock: .init(top: .purple, bottom: .blue),
            ),
            lockWidgetHeight: 76,
        ))
        #expect(featureDiscovery.widgets.contentWidth(in: 402) == 374)
        #expect(featureDiscovery.widgets.contentWidth(in: 834) == 320)
    }

    @Test func settingsPassportStyles() {
        #expect(style.passportSeal == .init(
            size: 52,
            rotationDegrees: -8,
            outerLineWidth: 2,
            innerLineWidth: 1,
            innerInset: 7,
            dashLength: 3,
            dashSpacing: 3,
            symbolFont: .title3,
        ))

        let privacy = style.privacyPassportCard
        #expect(privacy.cornerRadius == 20)
        #expect(privacy.padding == 16)
        #expect(privacy.sectionSpacing == 12)
        #expect(privacy.headerSpacing == 12)
        #expect(privacy.titleFont == .headline)
        #expect(privacy.detailFont == .subheadline)
        #expect(privacy.rosette == .init(
            wobble: 5,
            lineWidth: 0.75,
            primaryRingSpacing: 10,
            secondaryRingSpacing: 16,
            primaryOpacity: 0.1,
            secondaryOpacity: 0.06,
        ))
        #expect(privacy.reflectiveSurface == .init(
            backgroundTop: Color(red: 0.08, green: 0.18, blue: 0.34),
            backgroundBottom: Color(red: 0.02, green: 0.07, blue: 0.16),
            accent: Color(red: 0.88, green: 0.72, blue: 0.32),
            intensity: 0.28,
            staticGlintIntensity: 0.28,
            staticPose: .init(roll: 0.3, pitch: -0.15),
        ))
        #expect(privacy.disclosure == .init(
            rowSpacing: 8,
            cornerRadius: 12,
            padding: 10,
            contentSpacing: 10,
            textSpacing: 3,
            iconSize: 32,
            symbolFont: .subheadline,
            titleFont: .subheadline,
            detailFont: .footnote,
            statusFont: .footnote,
            statusHorizontalPadding: 8,
            statusVerticalPadding: 4,
            fillOpacity: 0.08,
            strokeOpacity: 0.18,
            strokeWidth: 0.75,
            statusFillOpacity: 0.14,
        ))
        #expect(privacy.outlineOpacity == 0.32)
        #expect(privacy.outlineWidth == 1)

        let source = style.openSourceStamp
        #expect(source.tint == .accentColor)
        #expect(source.padding == 16)
        #expect(source.contentSpacing == 12)
        #expect(source.titleFont == .headline)
        #expect(source.detailFont == .subheadline)
        #expect(source.outlineWidth == 1.5)
        #expect(source.rosette == .init(
            wobble: 5,
            lineWidth: 0.75,
            primaryRingSpacing: 10,
            secondaryRingSpacing: 16,
        ))
        #expect(source.ink == .standard)

        let warning = style.plannedStayWarningStamp
        #expect(warning.tint == .orange)
        #expect(warning.padding == 16)
        #expect(warning.contentSpacing == 12)
        #expect(warning.titleFont == .headline)
        #expect(warning.detailFont == .subheadline)
        #expect(warning.outlineWidth == 1.5)
        #expect(warning.rosette == source.rosette)
        #expect(warning.ink == .standard)
    }

    @Test func developerOverlayStyle() {
        let overlay = style.developerOverlay
        #expect(overlay.edgeInset == 16)
        #expect(overlay.presentationAnimation == .snappy(duration: 0.3))
        #expect(overlay.floatingWindow == .standard)
        #expect(overlay.floatingWindow.maxWidth == 420)
        #expect(overlay.floatingWindow.maxHeight == 620)
        #expect(overlay.floatingWindow.heightFraction == 0.62)
        #expect(overlay.floatingWindow.minSize == CGSize(width: 260, height: 320))
        #expect(overlay.floatingWindow.maxContentInsetFraction == 0.8)

        let panel = overlay.panel
        #expect(panel.cornerRadius == 22)
        #expect(panel.fullScreenInset == 12)
        #expect(panel.shadowOpacity == 0.3)
        #expect(panel.shadowRadius == 20)
        #expect(panel.shadowOffsetY == 6)
        #expect(panel.controlHorizontalPadding == 16)
        #expect(panel.controlVerticalPadding == 10)
        #expect(panel.dragHandleSize == CGSize(width: 40, height: 5))
        #expect(panel.dragHandleMinHeight == 28)
        #expect(panel.resizeGripSize == 44)
        #expect(panel.resizeIconSize == 13)
        #expect(panel.resizeGripClearance == 40)

        let menu = overlay.menu
        #expect(menu.maxWidth == 310)
        #expect(menu.launcherSpacing == 10)
        #expect(menu.rowSpacing == 8)
        #expect(menu.horizontalPadding == 14)
        #expect(menu.verticalPadding == 10)
        #expect(menu.minRowHeight == 44)
        #expect(menu.cornerRadius == 18)
        #expect(menu.subtitleSpacing == 2)
        #expect(menu.iconWidth == 24)
        #expect(menu.motion == .standard)
        #expect(menu.motion.animation == .spring(duration: 0.42, bounce: 0.2))
        #expect(menu.motion.stagger == 0.04)
        #expect(menu.motion.scale == 0.86)
        #expect(menu.motion.usesSpatialMotion)
    }

    @Test func paletteColors() {
        let palette = style.palette
        #expect(palette.primary.backgroundTop == Color(red: 0.07, green: 0.08, blue: 0.13))
        #expect(palette.primary.backgroundBottom == Color(red: 0.02, green: 0.02, blue: 0.05))
        #expect(palette.splash.background == Color(.systemBackground))
        #expect(palette.splash.vignetteCenter == Color(.secondarySystemBackground))
        #expect(palette.splash.vignetteEdge == Color(.systemBackground))
        #expect(palette.splash.iconGlow == .accentColor)
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
        #expect(resolved.calendar.day.minHeight == 56)
        #expect(resolved.timeline.overview.pinsToViewport == false)
        #expect(resolved.timeline.row.stacksDayCount)
        #expect(resolved.featureDiscovery.siri.bubble.indent == 0)
        #expect(resolved.featureDiscovery.widgets.contentWidth(in: 834) == 320)
    }

    @MainActor
    @Test func flattensCardGlowUnderReduceTransparency() throws {
        var context = BContext(traits: .system)
        context.traitOverrides.accessibility = BAccessibility(isReduceTransparencyEnabled: true)
        let resolved = try context.stylesheets.get(WhereStylesheet.self)
        #expect(resolved.card.regular.glow.radius == 0)
        #expect(resolved.card.compact.glow.radius == 0)
        #expect(resolved.card.constellation.haloOpacity == 0)
        #expect(resolved.card.constellation.coreOpacity == 0.92)
        #expect(resolved.privacyPassportCard.disclosure.fillOpacity == 0.16)
    }

    @MainActor
    @Test func strengthensSecurityInkWithDarkerSystemColors() throws {
        var context = BContext(traits: .system)
        context.traitOverrides.accessibility = BAccessibility(isDarkerSystemColorsEnabled: true)
        let resolved = try context.stylesheets.get(WhereStylesheet.self)
        #expect(resolved.locationForecast.ink == .increasedContrast)
        #expect(resolved.locationForecast.ink.microprintOpacity == 0.4)
        #expect(resolved.openSourceStamp.ink == .increasedContrast)
        #expect(resolved.plannedStayWarningStamp.ink == .increasedContrast)
    }

    @MainActor
    @Test func separatesRibbonRegionsWithoutColorDifferentiation() throws {
        var context = BContext(traits: .system)
        context.traitOverrides.accessibility = BAccessibility(
            shouldDifferentiateWithoutColor: true,
        )
        let resolved = try context.stylesheets.get(WhereStylesheet.self)
        #expect(resolved.timeline.overview.pinsToViewport == false)
        #expect(resolved.timeline.ribbon.separatesRegions)
    }

    @MainActor
    @Test func crossFadesTheCardDayCountUnderReduceMotion() throws {
        var context = BContext(traits: .system)
        context.traitOverrides.accessibility = BAccessibility(isReduceMotionEnabled: true)
        let resolved = try context.stylesheets.get(WhereStylesheet.self)
        #expect(resolved.card.dayCount == .reducedMotion)
        #expect(resolved.locationCardStack.overtake == .reducedMotion)
        #expect(resolved.locationCardStack.overtake.minimumOpacity == 0.82)
        #expect(resolved.locationCardStack.overtake.usesSpatialMotion == false)
        #expect(resolved.locationWelcome.motion == .reduced)
        #expect(resolved.locationWelcome.motion.usesSpatialMotion == false)
        #expect(resolved.developerOverlay.menu.motion == .reduced)
        #expect(resolved.developerOverlay.menu.motion.usesSpatialMotion == false)
    }

    @MainActor
    @Test func palesCardSecurityPrintInDarkMode() throws {
        var context = BContext(traits: .system)
        context.traitOverrides.mode = .dark
        let resolved = try context.stylesheets.get(WhereStylesheet.self)
        #expect(resolved.locationForecast == style.locationForecast)
        #expect(resolved.card.securityPrint == .dark)
        #expect(resolved.featureDiscovery.siri.accent == Color(white: 0.42))
        #expect(resolved.card.securityPrint.backgroundBlendMode == .luminosity)
        #expect(resolved.card.securityPrint.tint(.red) == Color.red.mix(
            with: .white,
            by: 0.65,
            in: .perceptual,
        ))
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

    @Test func whereBroadwayRootSeedsThemeIdentity() throws {
        let box = StylesheetProbeBox()
        let host = UIHostingController(
            rootView: StylesheetProbe(box: box)
                .whereBroadwayRoot(theme: .alternate),
        )
        try show(host) { _ in
            try waitFor { box.theme == .alternate }
        }
    }
}

private final class StylesheetProbeBox {
    var calendarDayMinHeight: CGFloat?
    var theme: WhereTheme?
}

private struct StylesheetProbe: View {
    let box: StylesheetProbeBox

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        Color.clear
            .onChange(of: stylesheet.calendar.day.minHeight, initial: true) { _, newValue in
                box.calendarDayMinHeight = newValue
            }
            .onChange(of: stylesheet.theme, initial: true) { _, newValue in
                box.theme = newValue
            }
    }
}
