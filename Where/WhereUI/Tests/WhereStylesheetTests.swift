import BroadwayCore
import BroadwayUI
import CoreGraphics
import SwiftUI
import TestHostSupport
import Testing
import UIKit
import WhereCore
@testable import WhereUI

/// Covers trait derivation, semantic constraints, and stylesheet calculations.
/// Component snapshots own authored appearance.
struct WhereStylesheetTests {
    @MainActor
    @Test(arguments: DynamicTypeSize.allCases)
    func launcherMatchesSwiftUIScaledMetric(size: DynamicTypeSize) throws {
        let box = ScaledDimensionProbeBox()
        let host = UIHostingController(rootView: ScaledDimensionProbe(box: box)
            .dynamicTypeSize(size))
        try show(host) { _ in
            try waitFor { box.value != nil }
            let measured = try #require(box.value)
            var context = BContext(traits: .system)
            context.traitOverrides.contentSizeCategory = .init(size)
            let sheet = try context.stylesheets.get(WhereStylesheet.self)
            let resolved = sheet.developerOverlay.launcher.diameter
            #expect(abs(measured - resolved) < 0.01)
        }
    }

    private let style = WhereStylesheet.default

    @Test func browseColumnCardsRetainTheirArtworkWithCompactTypography() {
        let column = style.card[.column]
        #expect(column.regionShape == style.card.regular.regionShape)
        #expect(column.sheen == style.card.regular.sheen)
        #expect(column.regionNameTypography == style.card.compact.regionNameTypography)
        #expect(column.entryStamp == style.card.compact.entryStamp)
    }

    @MainActor
    @Test(
        arguments: [UIUserInterfaceSizeClass.unspecified, .compact, .regular],
        [UIUserInterfaceSizeClass.unspecified, .compact, .regular],
    )
    func historyPanePolicyFollowsSystemSizeClasses(
        horizontal: UIUserInterfaceSizeClass,
        vertical: UIUserInterfaceSizeClass,
    ) throws {
        var context = BContext(traits: .system)
        context.traitOverrides.horizontalSizeClass = BHorizontalSizeClass(horizontal)
        context.traitOverrides.verticalSizeClass = BVerticalSizeClass(vertical)
        context.traitOverrides.contentSizeCategory = .init(DynamicTypeSize.large)
        let sheet = try context.stylesheets.get(WhereStylesheet.self)
        let expected: WhereStylesheet.AdaptivePaneStyle.Panes =
            horizontal == .regular && vertical == .regular ? .multiple : .single
        #expect(sheet.adaptivePane.panes == expected)
    }

    @MainActor
    @Test func accessibilityCollapsesHistoryWithoutChangingItsMeasuredLimits() throws {
        var context = BContext(traits: .system)
        context.traitOverrides.horizontalSizeClass = .regular
        context.traitOverrides.verticalSizeClass = .regular
        context.traitOverrides.contentSizeCategory = .init(DynamicTypeSize.large)
        let regular = try context.stylesheets.get(WhereStylesheet.self).adaptivePane
        #expect(regular.panes == .multiple)
        context.traitOverrides.contentSizeCategory = .init(DynamicTypeSize.accessibility1)
        let accessible = try context.stylesheets.get(WhereStylesheet.self).adaptivePane
        #expect(accessible.panes == .single)
        #expect(accessible.minimumDetailWidth == regular.minimumDetailWidth)
        #expect(accessible.minimumControlsWidth == regular.minimumControlsWidth)
    }

    @MainActor
    @Test(arguments: DynamicTypeSize.allCases)
    func resolvesComponentLayouts(size: DynamicTypeSize) throws {
        var context = BContext(traits: .system)
        context.traitOverrides.contentSizeCategory = .init(size)
        let sheet = try context.stylesheets.get(WhereStylesheet.self)
        let layout: WhereStylesheet.ContentLayout = size.isAccessibilitySize ? .stacked : .inline
        #expect(sheet.locationForecast.header.layout == layout)
        #expect(sheet.locationForecast.row.layout == layout)
        #expect(sheet.locationForecast.controls.layout == layout)
        #expect(sheet.locationForecast.controls.expandsClearAction == size.isAccessibilitySize)
        #expect(sheet.privacyPassportCard.headerLayout == layout)
        #expect(sheet.privacyPassportCard.disclosure.layout == layout)
        #expect(sheet.themePicker.layout == layout)
        #expect(sheet.yearModePicker.layout == layout)
        #expect(sheet.loggedDay.layout == layout)
        #expect(sheet.openSourceStamp.layout == layout)
        #expect(sheet.plannedStayWarningStamp.layout == layout)
        #expect(sheet.featureDiscovery.appIcon.layout == layout)
        #expect(sheet.featureDiscovery.regionStyle.layout == layout)
        #expect(sheet.featureDiscovery
            .shareSheet == (size.isAccessibilitySize ? .accessible : .standard))
        #expect(sheet.featureDiscovery
            .evidenceArchive == (size.isAccessibilitySize ? .accessible : .standard))
        #expect(sheet.locationWelcome.accessory
            .copy == (size.isAccessibilitySize ? .compact : .full))
        #expect(sheet.developerOverlay.launcher.diameter == BScaledDimension.value(
            52,
            relativeTo: .title2,
            category: .init(size),
        ))
    }

    @MainActor
    @Test(arguments: [false, true], [BMode.light, .dark])
    func resolvesAppearanceAndMotion(reducesMotion: Bool, mode: BMode) throws {
        var context = BContext(traits: .system)
        context.traitOverrides.mode = mode
        context.traitOverrides.accessibility = BAccessibility(isReduceMotionEnabled: reducesMotion)
        let sheet = try context.stylesheets.get(WhereStylesheet.self)
        #expect((sheet.regionPicker.selectionAnimation != nil) == !reducesMotion)
        #expect(sheet.settings.iconForeground == (mode == .dark ? Color.black : Color.white))
        #expect(sheet.settings
            .flashAnimation == (reducesMotion ? nil : style.settings.flashAnimation))
        #expect(sheet.launch.captionAnimation == (reducesMotion ? nil : style.motion.captionFade))
        #expect(sheet.launch.reveal == (reducesMotion ? .crossfade : .zoom))
        #expect(sheet.launch
            .revealAnimation == (reducesMotion ? style.motion.reducedReveal : style.motion.reveal))
    }

    @MainActor
    @Test func themesRetainDistinctIdentityAndSharedGeometry() throws {
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
        #expect(standard.card.regular.surface == .reflective)
        #expect(alternate.card.regular.surface.usesReflection == false)
        #expect(standard.card.regular.cornerRadius == alternate.card.regular.cornerRadius)
        #expect(standard.card.compact.padding == alternate.card.compact.padding)
        #expect(standard.card.regular.entryStamp == alternate.card.regular.entryStamp)
        #expect(standard.card.dayCount == alternate.card.dayCount)
        #expect(standard.locationCardStack == alternate.locationCardStack)
        #expect(standard.locationsBackground == alternate.locationsBackground)
        #expect(standard.yearModePicker == alternate.yearModePicker)
        #expect(standard.timeline == alternate.timeline)
    }

    @Test func interactiveTargetsMeetMinimumSize() {
        #expect(style.flightReviewPoint.minimumActionHeight >= 44)
        #expect(style.locationWelcome.accessory.minimumActionHeight >= 44)
        #expect(style.calendar.day.minHeight >= 44)
        #expect(style.locationForecast.controls.minimumHeight >= 44)
        #expect(style.regionPicker.colorSwatchMinWidth >= 44)
        #expect(style.regionPicker.glyphTileMinWidth >= 44)
        #expect(style.developerOverlay.panel.resizeGripSize >= 44)
        #expect(style.developerOverlay.menu.minRowHeight >= 44)
    }

    @Test func cardVariantSubscriptSelectsTheMatchingSpec() {
        #expect(style.card[.regular] == style.card.regular)
        #expect(style.card[.compact] == style.card.compact)
        #expect(style.card[.regular].showsProgress)
        #expect(style.card[.compact].showsProgress)
        let elsewhere = style.card[.elsewhere]
        #expect(elsewhere.paper == .light)
        #expect(elsewhere.showsProgress == false)
        #expect(elsewhere.padding == style.card.compact.padding)
        #expect(elsewhere.entryStamp == style.card.compact.entryStamp)
        #expect(elsewhere.regionShape == style.card.regular.regionShape)
        #expect(elsewhere.glow == .init(opacity: 0, radius: 0))
        #expect(elsewhere.lift == .init(opacity: 0, radius: 0))
    }

    @MainActor
    @Test(arguments: RegionColorToken.allCases, [BMode.light, .dark])
    func elsewherePaperKeepsEveryRegionTextReadable(color: RegionColorToken, mode: BMode) throws {
        var context = BContext(traits: .system)
        context.traitOverrides.mode = mode
        let sheet = try context.stylesheets.get(WhereStylesheet.self)
        let paper = try #require(sheet.card[.elsewhere].paper)
        #expect(paper == (mode == .dark ? .dark : .light))

        var environment = EnvironmentValues()
        environment.colorScheme = mode == .dark ? .dark : .light
        func luminance(_ color: Color) -> Double {
            let resolved = color.resolve(in: environment)
            func linear(_ channel: Float) -> Double {
                let value = Double(channel)
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(resolved.red)
                + 0.7152 * linear(resolved.green)
                + 0.0722 * linear(resolved.blue)
        }
        let ink = luminance(paper.contentTint.apply(to: color.color))
        let background = luminance(paper.surface.fill.base)
        let contrast = (max(ink, background) + 0.05) / (min(ink, background) + 0.05)
        #expect(contrast >= 4.5)
    }

    @Test func standardSecurityPrintPreservesRegionTint() {
        #expect(style.card.securityPrint.tint(.red) == .red)
    }

    /// The roll carries the count so it knows which way to spin the digits; the
    /// Reduce-Motion pairing drops the roll for a fade and ignores the count.
    @Test func dayCountTransitions() {
        let rolling = WhereStylesheet.CardStyles.DayCountStyle.standard
        #expect(rolling.morph == .rollingDigits)
        #expect(rolling.transition(days: 148) == .numericText(value: 148))
        #expect(rolling.transition(days: 149) != rolling.transition(days: 148))

        let reduced = WhereStylesheet.CardStyles.DayCountStyle.reducedMotion
        #expect(reduced.morph == .crossFade)
        #expect(reduced.transition(days: 148) == .opacity)
        #expect(reduced.transition(days: 149) == reduced.transition(days: 148))
    }

    @Test func timelineSizingDistinguishesSingleDayRows() {
        let row = style.timeline.row
        #expect(row.sizing(for: 1) == row.singleDay)
        #expect(row.sizing(for: 2).baseHeight == row.baseHeight)
        #expect(row.sizing(for: 2).verticalPadding == row.verticalPadding)
    }

    @Test func staggeredRevealRespectsMotionAndOrder() {
        let reveal = WhereStylesheet.Motion.StaggeredReveal(
            animation: .linear(duration: 1),
            verticalOffset: 8,
            delay: 0.25,
        )
        let hidden = reveal.presentation(isRevealed: false, motionIsStatic: false, order: 2)
        #expect(hidden.opacity == 0)
        #expect(hidden.verticalOffset == 8)
        #expect(hidden.animation == .linear(duration: 1).delay(0.5))
        #expect(reveal.presentation(isRevealed: false, motionIsStatic: true, order: 2) == .visible)
    }

    @Test func widgetExamplesFitSmallContainersAndConstrainLargeOnes() {
        var widgets = style.featureDiscovery.widgets
        widgets.device.padding = 15
        widgets.device.contentMaxWidth = 600
        widgets.device.regularContentWidth = 300
        #expect(widgets.contentWidth(in: 400) == 370)
        #expect(widgets.contentWidth(in: 800) == 300)
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
        #expect(resolved.calendar.overview.columns == 1)
        #expect(resolved.calendar.overview.titleFontSize == 22)
        #expect(resolved.calendar.compact.day.minHeight == 28)
        #expect(resolved.calendar.compact.day.numberFontSize == 16)
        #expect(resolved.calendar.day.minHeight == 56)
        #expect(resolved.calendar.day.numberSize == 36)
        #expect(resolved.calendar.day.numberFontSize == 24)
        #expect(resolved.calendar.month.weekdayFontSize == 14)
        #expect(resolved.calendar.month.stacksFooter)
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
        #expect(resolved.locationsBackground.showsInk == false)
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
        #expect(resolved.calendar.overview.usesSpatialMotion == false)
        #expect(resolved.calendar.overview.animation == .easeInOut(duration: 0.25))
        #expect(resolved.card.dayCount == .reducedMotion)
        #expect(resolved.locationCardStack.overtake == .reducedMotion)
        #expect(resolved.locationCardStack.overtake.minimumOpacity == 0.82)
        #expect(resolved.locationCardStack.overtake.usesSpatialMotion == false)
        #expect(resolved.locationWelcome.motion == .reduced)
        #expect(resolved.locationWelcome.motion.usesSpatialMotion == false)
        #expect(resolved.locationWelcome.motion.arrival == .init(
            animation: .easeInOut(duration: 0.16),
            scale: 1,
            rotationDegrees: 0,
            verticalOffset: 0,
        ))
        #expect(resolved.locationWelcome.motion.departure == resolved.locationWelcome.motion
            .arrival)
        #expect(resolved.locationWelcome.motion.scrimAnimation == .easeInOut(duration: 0.16))
        #expect(resolved.developerOverlay.menu.motion == .reduced)
        #expect(resolved.developerOverlay.menu.motion.usesSpatialMotion == false)
    }

    @MainActor
    @Test(arguments: [BMode.light, .dark], WhereTheme.allCases)
    func calendarOverviewInkRemainsDistinctFromDetail(mode: BMode, theme: WhereTheme) throws {
        var context = BContext(traits: .system)
        context.traitOverrides.mode = mode
        context.themes[WhereTheme.self] = theme
        let calendar = try context.stylesheets.get(WhereStylesheet.self).calendar
        let band = calendar.compact.regionBand
        #expect(band.opacity == (mode == .dark ? 0.55 : 0.4))
        #expect(band.planned.fillOpacity == (mode == .dark ? 0.24 : 0.16))
        #expect(band.planned.hatchOpacity == (mode == .dark ? 0.85 : 0.7))
        #expect(band.planned.hatchSpacing == 4)
        #expect(band.planned.hatchLineWidth == 1)
        #expect(calendar.compact.day.dotStrokeWidth > 0)
        #expect(calendar.regionBand == style.calendar.regionBand)
        #expect(calendar.month.plain.fill == .clear)
        #expect(calendar.month.current.fill == .clear)
        #expect(calendar.compact.month.plain.fill == .clear)
        #expect(calendar.compact.month.current.fill == .clear)
    }

    @MainActor
    @Test func palesCardSecurityPrintInDarkMode() throws {
        var context = BContext(traits: .system)
        context.traitOverrides.mode = .dark
        let resolved = try context.stylesheets.get(WhereStylesheet.self)
        var expectedForecast = style.locationForecast
        expectedForecast.summary.ink = Color(white: 0.78)
        expectedForecast.summary.paper = Color(white: 0.16)
        #expect(resolved.locationForecast == expectedForecast)
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

    @Test func updatesResolvedStylesWithEnvironmentChanges() throws {
        let box = StylesheetProbeBox()
        func content(size: DynamicTypeSize, mode: ColorScheme) -> some View {
            StylesheetProbe(box: box).whereBroadwayRoot()
                .dynamicTypeSize(size).environment(\.colorScheme, mode)
        }
        let host = UIHostingController(rootView: content(size: .large, mode: .light))
        try show(host) { _ in
            try waitFor { box.sheet?.locationForecast.header.layout == .inline }
            #expect(box.sheet?.settings.iconForeground == .white)
            host.rootView = content(size: .accessibility3, mode: .dark)
            try waitFor { box.sheet?.locationForecast.header.layout == .stacked }
            #expect(box.sheet?.settings.iconForeground == .black)
            host.rootView = content(size: .large, mode: .light)
            try waitFor { box.sheet?.locationForecast.header.layout == .inline }
            #expect(box.sheet?.settings.iconForeground == .white)
        }
    }

    @Test func scopedTraitsResolveCoordinatedStyles() throws {
        let box = StylesheetProbeBox()
        let host = UIHostingController(rootView: StylesheetProbe(box: box)
            .bContentSizeCategory(.small)
            .bMode(.dark)
            .bTraitOverrides { _, overrides in
                overrides.accessibility = BAccessibility(isReduceMotionEnabled: true)
            }
            .whereBroadwayRoot()
            .dynamicTypeSize(.accessibility3)
            .environment(\.colorScheme, .light))
        try show(host) { _ in
            try waitFor { box.sheet != nil }
            let sheet = try #require(box.sheet)
            #expect(sheet.locationForecast.header.layout == .inline)
            #expect(sheet.settings.iconForeground == .black)
            #expect(sheet.launch.reveal == .crossfade)
            #expect(sheet.launch.captionAnimation == nil)
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

    @Test func themeChangesUpdateMountedSurfacesInBothDirections() throws {
        let box = StylesheetProbeBox()
        func content(theme: WhereTheme) -> some View {
            StylesheetProbe(box: box).whereBroadwayRoot(theme: theme)
        }
        let host = UIHostingController(rootView: content(theme: .standard))
        try show(host) { _ in
            try waitFor { box.sheet?.card.regular.surface.usesReflection == true }
            host.rootView = content(theme: .alternate)
            try waitFor { box.sheet?.card.regular.surface.usesReflection == false }
            #expect(box.sheet?.privacyPassportCard.surface.usesReflection == false)
            host.rootView = content(theme: .standard)
            try waitFor { box.sheet?.card.regular.surface.usesReflection == true }
            #expect(box.sheet?.privacyPassportCard.surface.usesReflection == true)
        }
    }
}

private final class StylesheetProbeBox {
    var calendarDayMinHeight: CGFloat?
    var theme: WhereTheme?
    var sheet: WhereStylesheet?
}

private struct StylesheetProbe: View {
    let box: StylesheetProbeBox

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        Color.clear
            .onChange(of: stylesheet, initial: true) { _, value in box.sheet = value }
            .onChange(of: stylesheet.calendar.day.minHeight, initial: true) { _, newValue in
                box.calendarDayMinHeight = newValue
            }
            .onChange(of: stylesheet.theme, initial: true) { _, newValue in
                box.theme = newValue
            }
    }
}

private final class ScaledDimensionProbeBox {
    var value: CGFloat?
}

private struct ScaledDimensionProbe: View {
    let box: ScaledDimensionProbeBox
    @ScaledMetric(relativeTo: .title2) private var diameter: CGFloat = 52

    var body: some View {
        Color.clear.onChange(of: diameter, initial: true) { _, value in
            box.value = value
        }
    }
}
