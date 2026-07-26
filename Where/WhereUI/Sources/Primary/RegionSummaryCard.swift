import Foundation
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

    /// The calendar year being summarized, inked onto the entry stamp. Callers
    /// pass `WhereSession.selectedYear`; the default is only for previews.
    var year = WhereModel.currentYear

    /// Drives the holographic stamp sheen. The Primary tab passes its live
    /// `TiltProvider`; Elsewhere (and previews) pass `nil`, leaving a gentle
    /// static sheen.
    var tilt: TiltProvider?

    /// An explicit style to render instead of resolving the region's look from
    /// `\.regionStyles`. The region-customization screen passes the in-progress
    /// draft appearance so the card previews a pick before it's saved; every
    /// other caller leaves it `nil` and gets the resolved look.
    var styleOverride: RegionStyle?

    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.regionStyles) private var regionStyles

    /// The resolved spec for this card's variant, read once so the rest of the
    /// view is a straight-line render with no `compact` branching.
    private var card: WhereStylesheet.CardStyle {
        stylesheet.card[variant]
    }

    private var style: RegionStyle {
        styleOverride ?? regionStyles.style(for: regionDays.region)
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: card.cornerRadius, style: .continuous)
    }

    private var fraction: Double {
        guard yearLength > 0 else { return 0 }
        return min(1, Double(regionDays.days) / Double(yearLength))
    }

    private var barHeight: CGFloat {
        card.progressBarHeight
    }

    /// How a count change plays out while the card is on screen. Reduce Motion is
    /// already resolved into it by the stylesheet.
    private var dayCount: WhereStylesheet.CardStyles.DayCountStyle {
        stylesheet.card.dayCount
    }

    /// A circular rubber-stamp "entry" impression: the region glyph and year
    /// ringed by the region name, tilted as if pressed onto the page. The arc
    /// lettering is dropped on the small compact cards where it can't be read.
    private var entryStamp: some View {
        EntryStamp(
            title: regionDays.region.localizedName.uppercased(),
            year: year,
            symbolName: style.symbolName,
            tint: style.tint,
            size: card.entryStampSize,
            showsArcText: card.showsArcText,
        )
    }

    /// A faint, region-tinted "security print" behind the content: a guilloché
    /// rosette of subtly wobbling concentric rings plus an oversized region
    /// glyph watermarked into the corner, the way a passport page is printed
    /// beneath its stamps.
    private var stampPaper: some View {
        // Read the main-actor `style.tint` and the value-type `rosette` spec once
        // here so the nonisolated `Canvas` renderer closure captures `Sendable`
        // values rather than reaching back into main-actor state.
        let tint = style.tint
        let rosette = card.rosette
        let rosetteFill = stylesheet.card.rosetteFill
        return ZStack {
            Canvas { context, size in
                func drawRosette(center: CGPoint, spacing: CGFloat, opacity: Double) {
                    let ringCount = Int(max(size.width, size.height) / spacing)
                    for ring in 1 ... max(1, ringCount) {
                        let angle = Double(ring) * 0.55
                        let ringCenter = CGPoint(
                            x: center.x + CGFloat(cos(angle)) * rosette.wobble,
                            y: center.y + CGFloat(sin(angle)) * rosette.wobble,
                        )
                        let radius = CGFloat(ring) * spacing
                        let rect = CGRect(
                            x: ringCenter.x - radius,
                            y: ringCenter.y - radius,
                            width: radius * 2,
                            height: radius * 2,
                        )
                        context.stroke(
                            Path(ellipseIn: rect),
                            with: .color(tint.opacity(opacity)),
                            lineWidth: rosette.lineWidth,
                        )
                    }
                }
                // A bold rosette behind the stamp, plus a smaller, fainter one
                // in the opposite corner for denser, layered security print.
                drawRosette(
                    center: CGPoint(x: size.width * 0.8, y: size.height * 0.5),
                    spacing: rosette.primaryRingSpacing,
                    opacity: rosetteFill.primary,
                )
                drawRosette(
                    center: CGPoint(x: size.width * 0.12, y: size.height * 0.22),
                    spacing: rosette.secondaryRingSpacing,
                    opacity: rosetteFill.secondary,
                )
            }

            Image(systemName: style.symbolName)
                .font(.system(size: card.watermarkFontSize))
                .foregroundStyle(style.tint.opacity(stylesheet.card.watermarkOpacity))
                .rotationEffect(.degrees(-14))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .offset(x: card.watermarkOffset.width, y: card.watermarkOffset.height)
        }
        .clipShape(cardShape)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// A layered, official-looking frame: a heavy solid outer line, a thin solid
    /// line, a ring of perforation dots (Primary cards only), and a dashed inner
    /// line — like the engraved, perforated edge of a passport page.
    private var stampFrame: some View {
        let frame = stylesheet.card.frame
        return ZStack {
            cardShape
                .strokeBorder(
                    style.tint.opacity(frame.outerOpacity),
                    lineWidth: card.frameOuterLineWidth,
                )
            cardShape
                .inset(by: stylesheet.spacing.small)
                .strokeBorder(style.tint.opacity(frame.thinOpacity), lineWidth: frame.thinWidth)
            if card.showsPerforationRing {
                cardShape
                    .inset(by: stylesheet.spacing.large)
                    .strokeBorder(
                        style.tint.opacity(frame.perforationOpacity),
                        style: StrokeStyle(
                            lineWidth: frame.perforationWidth,
                            lineCap: .round,
                            dash: frame.perforationDash,
                        ),
                    )
            }
            cardShape
                .inset(by: card.innerFrameInset)
                .strokeBorder(
                    style.tint.opacity(frame.innerOpacity),
                    style: StrokeStyle(lineWidth: frame.innerWidth, dash: frame.innerDash),
                )
        }
        .allowsHitTesting(false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: card.contentSpacing) {
            HStack(alignment: .top, spacing: stylesheet.spacing.large) {
                VStack(alignment: .leading, spacing: stylesheet.spacing.xxSmall) {
                    Text(regionDays.region.localizedName)
                        .font(card.regionNameFont)
                        .tracking(card.regionNameTracking)
                        .lineLimit(1)
                        .allowsTightening(true)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(style.tint)
                        .opacity(stylesheet.card.nameOpacity)
                    if let caption {
                        Text(caption)
                            .font(.caption2.weight(.semibold))
                            .textCase(.uppercase)
                            .tracking(1)
                            .foregroundStyle(.secondary)
                    }
                    if let places {
                        Label(places, systemImage: "mappin.and.ellipse")
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
                    .font(card.heroNumberFont)
                    .contentTransition(dayCount.transition(days: regionDays.days))
                    .foregroundStyle(style.tint)
                Text(WhereFormat.dayUnit(regionDays.days))
                    .font(card.dayUnitFont)
                    .foregroundStyle(.secondary)
            }

            Capsule()
                .fill(.quaternary)
                .frame(height: barHeight)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(style.tint)
                            .frame(width: proxy.size.width * fraction)
                    }
                }
                .frame(height: barHeight)
                .accessibilityHidden(true)
        }
        // What makes the count's `.contentTransition` run at all — one morphs
        // only inside an animation transaction — and it sweeps the ambient bar,
        // which reads the same count, in the same beat.
        .animation(dayCount.animation, value: regionDays.days)
        .padding(card.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { stampPaper }
        .glassEffect(
            .regular.tint(style.tint.opacity(stylesheet.card.glassTintOpacity))
                .interactive(interactive),
            in: cardShape,
        )
        .holographicSheen(
            roll: tilt?.roll ?? 0,
            pitch: tilt?.pitch ?? 0,
            in: cardShape,
            tint: .white,
            intensity: card.holographicIntensity,
        )
        .overlay { stampFrame }
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
    }
}

/// A circular rubber-stamp impression — double ring, centered region glyph and
/// year, with the region name curved along the top arc — tilted as if an
/// official pressed it onto a passport page. Sizes scale off `size` so it reads
/// the same on the big Primary cards and the compact Elsewhere ones.
private struct EntryStamp: View {
    let title: String
    let year: Int
    let symbolName: String
    let tint: Color
    let size: CGFloat
    var showsArcText = true

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(tint.opacity(0.7), lineWidth: size * 0.035)
            Circle()
                .strokeBorder(
                    tint.opacity(0.45),
                    style: StrokeStyle(
                        lineWidth: size * 0.012,
                        dash: [size * 0.05, size * 0.035],
                    ),
                )
                .padding(size * 0.13)

            VStack(spacing: size * 0.02) {
                Image(systemName: symbolName)
                    .font(.system(size: size * 0.26))
                Text(verbatim: String(year))
                    .font(.system(size: size * 0.15, weight: .bold, design: .serif))
                    .monospacedDigit()
            }
            .foregroundStyle(tint.opacity(0.85))

            if showsArcText {
                ArcText(
                    text: title,
                    radius: size * 0.37,
                    font: .system(size: size * 0.1, weight: .semibold, design: .serif),
                    color: tint.opacity(0.7),
                )
            }
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(-8))
        .accessibilityHidden(true)
    }
}

/// Lays out `text` along the upper arc of a circle of the given `radius`,
/// centered at twelve o'clock — the curved lettering of a rubber stamp. The
/// angular span grows with the character count (capped) so short and long
/// region names both stay legible.
private struct ArcText: View {
    let text: String
    let radius: CGFloat
    let font: Font
    let color: Color

    var body: some View {
        let characters = Array(text)
        let sweep = min(250, Double(characters.count) * 17)
        ZStack {
            ForEach(Array(characters.enumerated()), id: \.offset) { index, character in
                Text(String(character))
                    .font(font)
                    .foregroundStyle(color)
                    .offset(y: -radius)
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
    }

    #Preview("Changing count") {
        ChangingCountPreview()
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
