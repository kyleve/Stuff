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

    @Test func signatureFolioFoundation() {
        #expect(style.seal == .init(
            outerRingWidth: 2,
            innerRingWidth: 0.75,
            innerRingInset: 7,
            meridianWidth: 0.75,
            meridianOpacity: 0.34,
            letterScale: 0.42,
            waypointScale: 0.075,
            waypointOffset: CGSize(width: 0.23, height: -0.2),
        ))

        let locations = style.locations
        #expect(locations.horizontalInset == 18)
        #expect(locations.topInset == 18)
        #expect(locations.mastheadSpacing == 12)
        #expect(locations.titleFont == .system(
            .largeTitle,
            design: .serif,
        ).weight(.semibold))
        #expect(locations.cardSpacing == 18)
        #expect(locations.featuredMinimumHeight == 300)
        #expect(locations.standardMinimumHeight == 248)
        #expect(locations.surfaceBorderOpacity == 0.12)
        #expect(locations.surfaceBorderWidth == 0.75)
    }

    @Test func regularCardStyle() {
        let card = style.card.regular
        #expect(style.card.estimatedProgressOpacity == 0.3)
        #expect(card.cornerRadius == 20)
        #expect(card.padding == 22)
        #expect(card.contentSpacing == 16)
        #expect(card.progressBarHeight == 3)
        #expect(card.entryStamp == expectedEntryStamp(size: 76, showsArcText: true))
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
            design: .default,
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
                fillOpacity: 0.065,
                stroke: .init(opacity: 0.13, width: 0.75),
            ),
            stamp: .init(
                center: CGPoint(x: 0.5, y: 0.5),
                extent: CGSize(width: 0.78, height: 0.78),
                scale: 0.88,
                fillOpacity: 0.68,
                stroke: nil,
            ),
            securityBorder: .init(
                inset: 9,
                glyphSize: 8,
                spacing: 11,
                opacity: 0.1,
            ),
        ))
        #expect(card.sheen == .init(
            intensity: 0.24,
            staticGlintIntensity: 0.07,
            staticPose: .init(roll: 0, pitch: -1),
        ))
        #expect(card.rosette == .init(
            wobble: 2,
            lineWidth: 0.75,
            primaryRingSpacing: 13.5,
            secondaryRingSpacing: 9.5,
        ))
        #expect(card.glow == .init(opacity: 0.04, radius: 3))
        #expect(card.lift == .init(opacity: 0.11, radius: 18, offsetY: 8))
    }

    @Test func compactCardStyle() {
        let card = style.card.compact
        #expect(card.cornerRadius == 18)
        #expect(card.padding == 16)
        #expect(card.contentSpacing == 10)
        #expect(card.progressBarHeight == 3)
        #expect(card.entryStamp == expectedEntryStamp(size: 52, showsArcText: false))
        #expect(card.regionNameTypography == .init(
            size: .semantic(.title3),
            weight: .semibold,
            design: .serif,
        ))
        #expect(card.heroNumberTypography == .init(
            size: .semantic(.title),
            weight: .bold,
            design: .default,
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
            intensity: 0.16,
            staticGlintIntensity: 0.06,
            staticPose: .init(roll: 0, pitch: 0),
        ))
        #expect(card.rosette == .init(
            wobble: 2,
            lineWidth: 1,
            primaryRingSpacing: 13,
            secondaryRingSpacing: 11,
        ))
        #expect(card.glow == .init(opacity: 0.03, radius: 2))
        #expect(card.lift == .init(opacity: 0.08, radius: 10, offsetY: 4))
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
        #expect(card.watermarkOpacity == 0.06)
        #expect(card.glassTintOpacity == 0.04)
        #expect(card.nameOpacity == 0.9)
        #expect(card.rosetteFill == .init(primary: 0.055, secondary: 0.03))
        #expect(card.securityPrint == .standard)
        #expect(card.securityPrint.backgroundBlendMode == .normal)
        #expect(card.securityPrint.tint(.red) == .red)
        #expect(card.dayCount == .standard)
        #expect(card.dayCount.revealDelay == .milliseconds(500))
        #expect(card.dayCount.animation == .smooth(duration: 0.36))
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
        #expect(reduced.animation == .easeInOut(duration: 0.18))
    }

    @Test func calendarStyle() {
        let calendar = style.calendar
        #expect(calendar.monthSpacing == 16)
        #expect(calendar.dotSize == 6)
        #expect(calendar.regionBand.opacity == 0.11)
        #expect(calendar.regionBand.height == 10)
        #expect(calendar.regionBand.cornerRadius == 5)
        #expect(calendar.regionBand.continuationRadius == 1.5)
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
        #expect(month.cornerRadius == 14)
        #expect(month.ruleSpacing == 32)
        #expect(month.ruleOpacity == 0.028)
        #expect(month.plain.fill == Color.primary.opacity(0.012))
        #expect(month.plain.border == Color.primary.opacity(0.14))
        #expect(month.plain.borderWidth == 0.75)
        #expect(month.plain.foreground == .primary)
        #expect(month.current.fill == Color.primary.opacity(0.035))
        #expect(month.current.border == Color.primary.opacity(0.32))
        #expect(month.current.borderWidth == 1)
        #expect(month.current.foreground == .primary)
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
        #expect(forecast.estimateSpacing == 3)
        #expect(forecast.collapsedLabelColor == Color.primary.opacity(0.5))
        #expect(forecast.borderColor == Color.primary.opacity(0.06))
        #expect(forecast.borderWidth == 0.5)
        #expect(forecast.shadowColor == Color.black.opacity(0.06))
        #expect(forecast.shadowRadius == 8)
        #expect(forecast.shadowOffsetY == 2)
        #expect(forecast.expansionAnimation == .easeInOut(duration: 0.2))
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
        #expect(overview.cornerRadius == 14)
        #expect(overview.background == Color.primary.opacity(0.012))
        #expect(overview.border == Color.primary.opacity(0.14))
        #expect(overview.borderWidth == 0.75)
        #expect(overview.yearFont == .system(.title2, design: .serif).bold())
        #expect(overview.pinsToViewport)

        let ribbon = timeline.ribbon
        #expect(ribbon.monthLabelSpacing == 6)
        #expect(ribbon.height == 10)
        #expect(ribbon.track == Color.primary.opacity(0.055))
        #expect(ribbon.border == Color.primary.opacity(0.16))
        #expect(ribbon.borderWidth == 0.75)
        #expect(ribbon.regionSpacing == 8)
        #expect(ribbon.regionLabelSpacing == 4)
        #expect(ribbon.separatesRegions == false)

        let rail = timeline.rail
        #expect(rail.lineWidth == 1.5)
        #expect(rail.toCardSpacing == 10)
        #expect(rail.nodeSize == 28)
        #expect(rail.nodeSymbolFont == .system(size: 12, weight: .semibold))
        #expect(rail.nodeEmojiFont == .system(size: 9))
        #expect(rail.charmOffset == CGSize(width: 9, height: 9))
        #expect(rail.nodeFillOpacity == 0.07)
        #expect(rail.nodeStrokeWidth == 1)

        let row = timeline.row
        #expect(row.spacing == 12)
        #expect(row.labelSpacing == 3)
        #expect(row.gap == 6)
        #expect(row.baseHeight == 68)
        #expect(row.yearScaleHeight == 0)
        #expect(row.horizontalPadding == 14)
        #expect(row.verticalPadding == 12)
        #expect(row.cornerRadius == 12)
        #expect(row.fillOpacity == 0)
        #expect(row.borderOpacity == 0.14)
        #expect(row.borderWidth == 0.75)
        #expect(row.countHorizontalPadding == 0)
        #expect(row.countVerticalPadding == 0)
        #expect(row.countFillOpacity == 0)
        #expect(row.durationScaleHeight == 3)
        #expect(row.stacksDayCount == false)

        let planned = timeline.planned
        #expect(planned.fillOpacity == 0.035)
        #expect(planned.borderOpacity == 0.14)
        #expect(planned.hatchOpacity == 0.16)
        #expect(planned.hatchSpacing == 8)
        #expect(planned.hatchLineWidth == 1)
        #expect(planned.labelOpacity == 0.7)
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
        #expect(evidence.archive == .init(
            cornerRadius: 16,
            padding: 16,
            rowSpacing: 12,
            indexWidth: 30,
            borderOpacity: 0.16,
            headerSealSize: 48,
            eyebrowFont: .caption2.weight(.semibold),
            titleFont: .system(.title2, design: .serif).weight(.semibold),
            rowTitleFont: .system(.headline, design: .serif).weight(.semibold),
            indexFont: .caption2.weight(.semibold).monospacedDigit(),
        ))
        #expect(evidence.compose == .init(
            sealSize: 44,
            eyebrowFont: .caption2.weight(.semibold),
            titleFont: .system(.title3, design: .serif).weight(.semibold),
        ))
    }

    @Test func elsewhereCardStyle() {
        let card = style.elsewhereCard
        #expect(card.cornerRadius == 22)
        #expect(card.padding == 18)
        #expect(card.iconPointSize == 28)
    }

    @Test func typographyFaces() {
        let typography = style.typography
        #expect(typography.onboardingIcon == .system(size: 34, weight: .regular))
        #expect(typography.editorialTitle == .system(.largeTitle, design: .serif).bold())
        #expect(typography.instrumentNumber == .system(
            .largeTitle,
            design: .default,
        ).bold().monospacedDigit())
        #expect(typography.widgetHeroRegion == .system(.headline, design: .serif).weight(.semibold))
        #expect(typography.widgetTotalNumber == .system(
            .body,
            design: .default,
            weight: .bold,
        ).monospacedDigit())
    }

    @Test func motionAnimations() {
        let motion = style.motion
        #expect(motion.response == .smooth(duration: 0.18))
        #expect(motion.settle == .smooth(duration: 0.36))
        #expect(motion.reveal == .easeOut(duration: 0.42))
        #expect(motion.ceremonial == .smooth(duration: 0.62))
        #expect(motion.reduced == .easeInOut(duration: 0.18))
        #expect(motion.captionFade == .easeOut(duration: 0.28))
        #expect(motion.staggeredReveal.animation == .easeOut(duration: 0.42))
        #expect(motion.staggeredReveal.verticalOffset == 10)
        #expect(motion.staggeredReveal.delay == 0.05)

        let hidden = motion.staggeredReveal.presentation(
            isRevealed: false,
            motionIsStatic: false,
            order: 2,
        )
        #expect(hidden.opacity == 0)
        #expect(hidden.verticalOffset == 10)
        #expect(hidden.animation == .easeOut(duration: 0.42).delay(0.1))

        let capped = motion.staggeredReveal.presentation(
            isRevealed: false,
            motionIsStatic: false,
            order: 8,
        )
        #expect(capped.animation == .easeOut(duration: 0.42).delay(0.1))

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
        #expect(launch.revealAnimation == .smooth(duration: 0.62))
        #expect(launch.reducedRevealAnimation == .easeInOut(duration: 0.18))
        #expect(launch.sealSize == 132)
        #expect(launch.coverInset == 22)
        #expect(launch.coverCornerRadius == 28)
    }

    @Test func onboardingStyle() {
        let onboarding = style.onboarding
        #expect(onboarding.brandMarkSize == 72)
        #expect(onboarding.primaryButtonCornerRadius == 18)
        #expect(onboarding.primaryButtonVerticalPadding == 14)
        #expect(onboarding.primaryButtonPressedScale == 0.99)
        #expect(onboarding.motion == .standard)
        #expect(onboarding.motion.animation == .smooth(duration: 0.4))
    }

    @Test func yearStyle() {
        #expect(style.year.motion == .standard)
        #expect(style.year.motion.contentAnimation == .smooth(duration: 0.36))
        #expect(style.year.cover == .init(
            cornerRadius: 28,
            horizontalPadding: 26,
            verticalPadding: 30,
            minimumHeight: 570,
            sealSize: 72,
            titleFont: .system(.largeTitle, design: .serif).weight(.semibold),
            eyebrowFont: .caption2.weight(.semibold),
            figureNumberFont: .title2.weight(.semibold).monospacedDigit(),
            figureEditorialFont: .system(.title2, design: .serif).weight(.semibold),
            figureLabelFont: .caption.weight(.medium),
            figureSpacing: 18,
            borderOpacity: 0.32,
            borderWidth: 0.75,
            actionHorizontalPadding: 18,
            actionVerticalPadding: 11,
        ))
    }

    @Test func recordPreparationStyle() {
        #expect(style.recordPreparation == .init(
            cornerRadius: 22,
            padding: 22,
            sectionSpacing: 18,
            sealSize: 58,
            borderOpacity: 0.42,
            eyebrowFont: .caption2.weight(.semibold),
            titleFont: .system(.title2, design: .serif).weight(.semibold),
            figureFont: .subheadline.weight(.semibold).monospacedDigit(),
            statusFont: .headline,
            metadataLabelFont: .caption.weight(.medium),
            metadataValueFont: .subheadline,
        ))
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

    @Test func passportCardStyle() {
        let source = style.passportCard
        #expect(source.cornerRadius == 20)
        #expect(source.padding == 16)
        #expect(source.contentSpacing == 12)
        #expect(source.titleFont == .headline)
        #expect(source.detailFont == .subheadline)
        #expect(source.seal == .init(
            size: 52,
            rotationDegrees: -8,
            outerLineWidth: 2,
            innerLineWidth: 1,
            innerInset: 7,
            dashLength: 3,
            dashSpacing: 3,
            symbolFont: .title3,
        ))
        #expect(source.rosette == .init(
            wobble: 5,
            lineWidth: 0.75,
            primaryRingSpacing: 10,
            secondaryRingSpacing: 16,
            primaryOpacity: 0.06,
            secondaryOpacity: 0.035,
        ))
        #expect(source.reflectiveSurface == .init(
            backgroundTop: Color(red: 0.07, green: 0.14, blue: 0.25),
            backgroundBottom: Color(red: 0.025, green: 0.055, blue: 0.11),
            accent: Color(red: 0.72, green: 0.56, blue: 0.27),
            glowOpacity: 0.035,
            intensity: 0.1,
            staticGlintIntensity: 0.06,
            staticPose: .init(roll: 0.3, pitch: -0.15),
        ))
        #expect(source.glassTintOpacity == 0.03)
        #expect(source.accentGlow == .init(opacity: 0.05, radius: 4))
        #expect(source.liftShadow == .init(opacity: 0.1, radius: 9, offsetY: 4))
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
        #expect(palette.brand == .standard)
        #expect(palette.primary.backgroundTop == Color(red: 0.07, green: 0.08, blue: 0.13))
        #expect(palette.primary.backgroundBottom == Color(red: 0.02, green: 0.02, blue: 0.05))
        #expect(palette.splash.background == Color(.systemBackground))
        #expect(palette.splash.vignetteCenter == Color(.secondarySystemBackground))
        #expect(palette.splash.vignetteEdge == Color(.systemBackground))
        #expect(palette.splash.iconGlow == .accentColor)
        #expect(palette.onboarding.backgroundTop == WhereStylesheet.Palette.Brand.standard
            .raisedPaper)
        #expect(palette.onboarding.backgroundBottom == WhereStylesheet.Palette.Brand.standard
            .canvas)
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
        #expect(resolved.onboarding.motion == .reduced)
        #expect(resolved.onboarding.motion.animation == .easeInOut(duration: 0.18))
        #expect(resolved.year.motion == .reduced)
        #expect(resolved.year.motion.contentAnimation == .easeInOut(duration: 0.18))
        #expect(resolved.developerOverlay.menu.motion == .reduced)
        #expect(resolved.developerOverlay.menu.motion.usesSpatialMotion == false)
    }

    @MainActor
    @Test func palesCardSecurityPrintInDarkMode() throws {
        var context = BContext(traits: .system)
        context.traitOverrides.mode = .dark
        let resolved = try context.stylesheets.get(WhereStylesheet.self)
        #expect(resolved.card.securityPrint == .dark)
        #expect(resolved.featureDiscovery.siri.accent == Color(white: 0.42))
        #expect(resolved.palette == .dark)
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
