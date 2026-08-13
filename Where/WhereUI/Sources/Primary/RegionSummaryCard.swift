import Foundation
import RegionKit
import SFSafeSymbols
import SwiftUI
import WhereCore

/// A Liquid Glass card summarizing how many days were spent in one region.
/// Used prominently on the Primary tab and (more compactly) on Elsewhere.
struct RegionSummaryCard: View {
    let regionDays: RegionDays
    var caption: String?
    /// An optional reverse-geocoded "where" teaser (e.g. "Paris, France"),
    /// shown beneath the caption. Used on the Elsewhere cards; `nil` on the
    /// Locations cards, which intentionally stay a pure passport stamp.
    var places: String?

    /// Which card spec to render — the big `.regular` Locations card or the
    /// `.compact` Elsewhere one. The caller picks; the view reads the one
    /// resolved ``WhereStylesheet/CardStyle`` and never branches on it again.
    var variant: WhereStylesheet.CardStyle.Variant = .regular

    /// When `true`, the card's Liquid Glass reacts to touch with the system's
    /// interactive press (scale + illumination), so a tappable card feels
    /// physical without a custom animation. The Primary cards opt in; the
    /// display-only / link cards leave it `false`.
    var interactive = false

    /// Calendar days in the year being summarized; the ambient bar is drawn as
    /// a fraction of this. Callers pass the selected year's real length
    /// (`YearReportModel.daysInSelectedYear`); the default is only for previews.
    var yearLength = 365

    /// The forecasted total rendered behind recorded progress. Locations cards
    /// supply it when Estimated Time & Planning is visible; other cards omit it.
    var estimatedDays: Int?

    /// The calendar year being summarized, inked onto the entry stamp. Callers
    /// pass `WhereSession.selectedYear`; the default is only for previews.
    var year = WhereModel.currentYear

    /// Drives the card's light sheen. Locations and the region editor pass a
    /// live `TiltProvider`; callers without one use the card's static pose.
    var tilt: TiltProvider?

    /// An explicit style to render instead of resolving the region's look from
    /// `\.regionStyles`. The region-customization screen passes the in-progress
    /// draft appearance so the card previews a pick before it's saved; every
    /// other caller leaves it `nil` and gets the resolved look.
    var styleOverride: RegionStyle?

    /// Raw recorded fixes for the region's selected year. Locations cards pass
    /// these in; every other card keeps the empty zero-value treatment.
    var recordedPoints: [RegionDayPoint] = []

    /// Whether the card renders `recordedPoints`. Locations binds this to the
    /// user's Appearance preference so hiding dots leaves the raw data intact.
    var showsRecordedPoints = true

    /// Identity of the loaded recorded-point snapshot. Locations supplies it to
    /// restart projection only when the underlying point content changes.
    var recordedPointsID: PrimaryRegionLocations.ID?

    /// Loaded from the root-owned UI path cache. The large watermark uses
    /// medium fidelity, the stamp uses small, and the repeated border uses
    /// micro. Point-only refreshes retain the previous value until its updated
    /// constellation is ready, so the static artwork never blinks out.
    @State private var regionPaths: RegionArtworkPaths?

    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.regionStyles) private var regionStyles
    @Environment(\.regionOutlinePathCache) private var regionOutlinePathCache
    #if DEBUG
        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.cardDesignerConfiguration) private var cardDesignerConfiguration
    #endif

    private var cardStyles: WhereStylesheet.CardStyles {
        #if DEBUG
            if let cardDesignerConfiguration {
                return cardDesignerConfiguration.resolve(
                    over: stylesheet.card,
                    colorScheme: colorScheme,
                )
            }
        #endif
        return stylesheet.card
    }

    /// The resolved spec for this card's variant, read once so the rest of the
    /// view is a straight-line render with no `compact` branching.
    private var card: WhereStylesheet.CardStyle {
        cardStyles[variant]
    }

    private var style: RegionStyle {
        styleOverride ?? regionStyles.style(for: regionDays.region)
    }

    private var recordedFraction: Double {
        fraction(for: regionDays.days)
    }

    private var estimatedFraction: Double? {
        estimatedDays.map(fraction)
    }

    /// Region ink on light cards; a pale derivative on dark cards that remains
    /// distinct while interactive Liquid Glass illuminates nearby surfaces.
    private var securityPrintTint: Color {
        cardStyles.securityPrint.tint(style.tint)
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: card.cornerRadius, style: .continuous)
    }

    private var barHeight: CGFloat {
        card.progressBarHeight
    }

    private func fraction(for days: Int) -> Double {
        guard yearLength > 0 else { return 0 }
        return min(1, max(0, Double(days) / Double(yearLength)))
    }

    private var regionArtworkLoadID: RegionArtworkLoadID {
        RegionArtworkLoadID(
            region: regionDays.region,
            variant: variant,
            isEnabled: card.regionShape != nil,
            showsRecordedPoints: showsRecordedPoints,
            recordedPointsID: recordedPointsID,
        )
    }

    /// How a count change plays out while the card is on screen. Reduce Motion is
    /// already resolved into it by the stylesheet.
    private var dayCount: WhereStylesheet.CardStyles.DayCountStyle {
        cardStyles.dayCount
    }

    /// A circular rubber-stamp "entry" impression: the region glyph and year
    /// ringed by the region name, tilted as if pressed onto the page. The arc
    /// lettering is dropped on the small compact cards where it can't be read.
    private var entryStamp: some View {
        EntryStamp(
            title: regionDays.region.localizedName.uppercased(),
            year: year,
            symbol: style.symbol,
            tint: securityPrintTint,
            style: card.entryStamp,
            regionPath: regionPaths?.stamp ?? Path(),
            regionShape: card.regionShape,
        )
    }

    /// A faint, region-tinted "security print" behind the content: a guilloché
    /// rosette of subtly wobbling concentric rings plus an oversized region
    /// glyph and microprinted silhouette border, the way a passport page is
    /// printed beneath its stamps.
    private var stampPaper: some View {
        // Read the main-actor `style.tint` and the value-type `rosette` spec once
        // here so the nonisolated `Canvas` renderer closure captures `Sendable`
        // values rather than reaching back into main-actor state.
        let tint = securityPrintTint
        let rosette = card.rosette
        let rosetteFill = cardStyles.rosetteFill
        return ZStack {
            SecurityPrintRosette(
                tint: tint,
                wobble: rosette.wobble,
                lineWidth: rosette.lineWidth,
                primaryRingSpacing: rosette.primaryRingSpacing,
                secondaryRingSpacing: rosette.secondaryRingSpacing,
                primaryOpacity: rosetteFill.primary,
                secondaryOpacity: rosetteFill.secondary,
            )

            if
                let regionShape = card.regionShape,
                let regionPath = regionPaths?.microprint,
                !regionPath.isEmpty
            {
                RegionOutlineSecurityBorder(
                    path: regionPath,
                    tint: tint,
                    cornerRadius: card.cornerRadius,
                    style: regionShape.securityBorder,
                )
            }

            if
                let regionShape = card.regionShape,
                let regionPath = regionPaths?.watermark,
                !regionPath.isEmpty
            {
                RegionOutlineArtwork(
                    path: regionPath,
                    tint: tint,
                    style: regionShape.watermark,
                    constellationPoints: showsRecordedPoints
                        ? regionPaths?.constellation ?? []
                        : [],
                    constellationStyle: cardStyles.constellation,
                )
            } else {
                Image(systemSymbol: style.symbol)
                    .font(.system(size: card.watermarkFontSize))
                    .foregroundStyle(tint.opacity(cardStyles.watermarkOpacity))
                    .rotationEffect(.degrees(-14))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .offset(x: card.watermarkOffset.width, y: card.watermarkOffset.height)
            }
        }
        .blendMode(cardStyles.securityPrint.backgroundBlendMode)
        .clipShape(cardShape)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func loadRegionOutlines() async {
        let staticArtworkID = regionArtworkLoadID.staticArtworkID
        if regionPaths?.staticArtworkID != staticArtworkID {
            regionPaths = nil
        }
        guard card.regionShape != nil, let regionOutlinePathCache else { return }
        async let watermark = regionOutlinePathCache.path(
            for: regionDays.region,
            resolution: .medium,
        )
        async let stamp = regionOutlinePathCache.path(
            for: regionDays.region,
            resolution: .small,
        )
        async let microprint = regionOutlinePathCache.path(
            for: regionDays.region,
            resolution: .micro,
        )
        let visibleRecordedPoints = showsRecordedPoints ? recordedPoints : []
        async let projectedPoints = regionOutlinePathCache.projectedPoints(
            for: regionDays.region,
            points: visibleRecordedPoints,
        )
        let (watermarkPath, stampPath, microprintPath, projected) = await (
            watermark,
            stamp,
            microprint,
            projectedPoints,
        )
        guard Task.isCancelled == false else { return }
        let constellation = cardStyles.constellation
        let loaded = RegionArtworkPaths(
            staticArtworkID: staticArtworkID,
            watermark: watermarkPath,
            stamp: stampPath,
            microprint: microprintPath,
            constellation: RegionLocationConstellationLayout.selectedPoints(
                from: projected,
                inside: watermarkPath,
                gridResolution: constellation.gridResolution,
                maximumCount: constellation.maximumPointCount,
            ),
        )
        regionPaths = loaded
    }

    var body: some View {
        VStack(alignment: .leading, spacing: card.contentSpacing) {
            HStack(alignment: .top, spacing: stylesheet.spacing.large) {
                VStack(alignment: .leading, spacing: stylesheet.spacing.xxSmall) {
                    Text(regionDays.region.localizedName)
                        .font(card.regionNameTypography.font)
                        .tracking(card.regionNameTracking)
                        .lineLimit(1)
                        .allowsTightening(true)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(style.tint)
                        .opacity(cardStyles.nameOpacity)
                    if let caption {
                        Text(caption)
                            .font(.caption2.weight(.semibold))
                            .textCase(.uppercase)
                            .tracking(1)
                            .foregroundStyle(.secondary)
                    }
                    if let places {
                        Label(places, systemSymbol: .mappinAndEllipse)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(style.tint)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                entryStamp
            }

            HStack(alignment: .firstTextBaseline, spacing: stylesheet.spacing.small) {
                Text(regionDays.days, format: .number)
                    .font(card.heroNumberTypography.font)
                    .contentTransition(dayCount.transition(days: regionDays.days))
                    .foregroundStyle(style.tint)
                Text(WhereFormat.dayUnit(regionDays.days))
                    .font(card.dayUnitTypography.font)
                    .foregroundStyle(.secondary)
            }

            Capsule()
                .fill(.quaternary)
                .frame(height: barHeight)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(style.tint)
                            .frame(width: proxy.size.width * recordedFraction)
                            .background(alignment: .leading) {
                                if let estimatedFraction {
                                    Capsule()
                                        .fill(style.tint.opacity(
                                            cardStyles.estimatedProgressOpacity,
                                        ))
                                        .frame(width: proxy.size.width * estimatedFraction)
                                }
                            }
                    }
                }
                .frame(height: barHeight)
                .accessibilityHidden(true)
        }
        // What makes the count's `.contentTransition` run at all — one morphs
        // only inside an animation transaction — and it sweeps the ambient bar,
        // which reads the same count, in the same beat.
        .animation(dayCount.animation, value: regionDays.days)
        .animation(dayCount.animation, value: estimatedDays)
        .padding(card.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { stampPaper }
        .glassEffect(
            .regular.tint(style.tint.opacity(cardStyles.glassTintOpacity))
                .interactive(interactive),
            in: cardShape,
        )
        .tiltSheen(
            tilt: tilt,
            staticRoll: card.sheen.staticPose.roll,
            staticPitch: card.sheen.staticPose.pitch,
            in: cardShape,
            intensity: card.sheen.intensity,
            staticGlintIntensity: card.sheen.staticGlintIntensity,
        )
        .clipShape(cardShape)
        // Make the whole card a single hit target — without this only the
        // opaque sub-views (text, stamp, bar) take taps, leaving dead gaps
        // (e.g. the bottom-right) when the card is wrapped in a Button/link.
        .contentShape(cardShape)
        .shadow(
            color: style.tint.opacity(card.glow.opacity),
            radius: card.glow.radius,
        )
        .shadow(
            color: style.tint.opacity(card.lift.opacity),
            radius: card.lift.radius,
            y: card.lift.offsetY,
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            WhereFormat.regionDaysAccessibility(
                region: regionDays.region.localizedName,
                days: regionDays.days,
            ),
        )
        .task(id: regionArtworkLoadID, loadRegionOutlines)
    }
}

/// Restarts cached artwork loading when a designer changes the outline treatment
/// or the user changes GPS-dot visibility without changing the card's region.
struct RegionArtworkLoadID: Equatable {
    struct StaticArtworkID: Equatable {
        let region: Region
        let variant: WhereStylesheet.CardStyle.Variant
        let isEnabled: Bool
    }

    let region: Region
    let variant: WhereStylesheet.CardStyle.Variant
    let isEnabled: Bool
    let showsRecordedPoints: Bool
    let recordedPointsID: PrimaryRegionLocations.ID?

    var staticArtworkID: StaticArtworkID {
        StaticArtworkID(
            region: region,
            variant: variant,
            isEnabled: isEnabled,
        )
    }
}

/// A circular rubber-stamp impression — double ring, centered region glyph and
/// year, with the region name curved along the top arc — tilted as if an
/// official pressed it onto a passport page. The card stylesheet owns its
/// complete drawing treatment for both regular and compact cards.
private struct EntryStamp: View {
    let title: String
    let year: Int
    let symbol: SFSymbol
    let tint: Color
    let style: WhereStylesheet.CardStyle.EntryStamp
    let regionPath: Path
    let regionShape: WhereStylesheet.CardStyle.RegionShape?

    var body: some View {
        let size = style.size
        ZStack {
            Circle()
                .strokeBorder(
                    tint.opacity(style.outerRing.opacity),
                    lineWidth: size * style.outerRing.lineWidthFraction,
                )
            Circle()
                .strokeBorder(
                    tint.opacity(style.innerRing.opacity),
                    style: StrokeStyle(
                        lineWidth: size * style.innerRing.lineWidthFraction,
                        dash: [
                            size * style.innerRing.dash.lengthFraction,
                            size * style.innerRing.dash.spacingFraction,
                        ],
                    ),
                )
                .padding(size * style.innerRing.insetFraction)

            VStack(spacing: size * style.content.spacingFraction) {
                if let regionShape, !regionPath.isEmpty {
                    RegionOutlineArtwork(
                        path: regionPath,
                        tint: tint,
                        style: regionShape.stamp,
                    )
                    .frame(
                        width: size * style.content.artworkExtent.width,
                        height: size * style.content.artworkExtent.height,
                    )
                } else {
                    Image(systemSymbol: symbol)
                        .font(style.content.symbolFont.font(for: size))
                }
                Text(verbatim: String(year))
                    .font(style.content.yearFont.font(for: size))
                    .monospacedDigit()
            }
            .foregroundStyle(tint.opacity(style.content.opacity))

            if let arc = style.arc {
                ArcText(
                    text: title,
                    size: size,
                    tint: tint,
                    style: arc,
                )
            }
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(style.rotationDegrees))
        .accessibilityHidden(true)
    }
}

/// The cached render artifacts a regular card consumes together.
private struct RegionArtworkPaths {
    let staticArtworkID: RegionArtworkLoadID.StaticArtworkID
    let watermark: Path
    let stamp: Path
    let microprint: Path
    let constellation: [RegionLocationConstellationLayout.Point]
}

/// Lays out `text` along the upper arc of a circle of the given `radius`,
/// centered at twelve o'clock — the curved lettering of a rubber stamp. The
/// angular span grows with the character count (capped) so short and long
/// region names both stay legible.
private struct ArcText: View {
    let text: String
    let size: CGFloat
    let tint: Color
    let style: WhereStylesheet.CardStyle.EntryStamp.Arc

    var body: some View {
        let characters = Array(text)
        let sweep = min(
            style.maximumSweepDegrees,
            Double(characters.count) * style.sweepDegreesPerCharacter,
        )
        ZStack {
            ForEach(Array(characters.enumerated()), id: \.offset) { index, character in
                Text(String(character))
                    .font(style.font.font(for: size))
                    .foregroundStyle(tint.opacity(style.opacity))
                    .offset(y: -size * style.radiusFraction)
                    .rotationEffect(angle(at: index, count: characters.count, sweep: sweep))
            }
        }
    }

    private func angle(at index: Int, count: Int, sweep: Double) -> Angle {
        guard count > 1 else { return .zero }
        let fraction = Double(index) / Double(count - 1) - 0.5
        return .degrees(fraction * sweep)
    }
}

#if DEBUG
    #Preview {
        VStack {
            RegionSummaryCard(
                regionDays: RegionDays(region: .california, days: 148),
                caption: "Home base",
                year: 2026,
            )
            RegionSummaryCard(
                regionDays: RegionDays(region: .europeanUnion, days: 22),
                variant: .compact,
                year: 2026,
            )
        }
        .padding()
        .whereBroadwayRoot()
    }

    #Preview("Changing count") {
        ChangingCountPreview()
            .whereBroadwayRoot()
    }

    /// Stands in for the count changing under the user, which is otherwise only
    /// reachable by waiting for a sample to land: stepping the count plays the
    /// same morph the live card does.
    private struct ChangingCountPreview: View {
        @State private var days = 148

        var body: some View {
            VStack {
                RegionSummaryCard(
                    regionDays: RegionDays(region: .california, days: days),
                    caption: "Home base",
                    year: 2026,
                )
                Stepper(value: $days, in: 0 ... 365) {
                    Text(verbatim: "Days: \(days)")
                }
            }
            .padding()
        }
    }
#endif
