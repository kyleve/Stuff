import Foundation
import StuffCore
import SwiftUI
import WhereCore

/// A Liquid Glass card summarizing how many days were spent in one region.
/// Used prominently on the Primary tab and (more compactly) on Elsewhere.
struct RegionSummaryCard: View {
    let regionDays: RegionDays
    var caption: String?
    /// An optional reverse-geocoded "where" teaser (e.g. "Paris, France"),
    /// shown beneath the caption. Used on the Elsewhere cards; `nil` on
    /// Primary, which intentionally stays a pure passport stamp.
    var places: String?
    var compact = false

    /// Calendar days in the year being summarized; the ambient bar is drawn as
    /// a fraction of this. Callers pass the selected year's real length
    /// (`WhereSession.daysInSelectedYear`); the default is only for previews.
    var yearLength = 365

    /// The calendar year being summarized, inked onto the entry stamp. Callers
    /// pass `WhereSession.selectedYear`; the default is only for previews.
    var year = Calendar.current.component(.year, from: Date())

    /// Drives the holographic stamp sheen. The Primary tab passes its live
    /// `TiltProvider`; Elsewhere (and previews) pass `nil`, leaving a gentle
    /// static sheen.
    var tilt: TiltProvider?

    private var style: RegionStyle {
        regionDays.region.style
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: compact ? UIConstants.CornerRadius.compactCard : UIConstants
                .CornerRadius.card,
            style: .continuous,
        )
    }

    private var fraction: Double {
        guard yearLength > 0 else { return 0 }
        return min(1, Double(regionDays.days) / Double(yearLength))
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
            size: compact ? UIConstants.Size.entryStampCompact : UIConstants.Size.entryStamp,
            showsArcText: !compact,
        )
    }

    /// A faint, region-tinted "security print" behind the content: a guilloché
    /// rosette of subtly wobbling concentric rings plus an oversized region
    /// glyph watermarked into the corner, the way a passport page is printed
    /// beneath its stamps.
    private var stampPaper: some View {
        ZStack {
            Canvas { context, size in
                let wobble: CGFloat = compact ? 2 : 3
                let lineWidth: CGFloat = compact ? 2 : 3
                func rosette(center: CGPoint, spacing: CGFloat, opacity: Double) {
                    let ringCount = Int(max(size.width, size.height) / spacing)
                    for ring in 1 ... max(1, ringCount) {
                        let angle = Double(ring) * 0.55
                        let ringCenter = CGPoint(
                            x: center.x + CGFloat(cos(angle)) * wobble,
                            y: center.y + CGFloat(sin(angle)) * wobble,
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
                            with: .color(style.tint.opacity(opacity)),
                            lineWidth: lineWidth,
                        )
                    }
                }
                // A bold rosette behind the stamp, plus a smaller, fainter one
                // in the opposite corner for denser, layered security print.
                rosette(
                    center: CGPoint(x: size.width * 0.8, y: size.height * 0.5),
                    spacing: compact ? 13 : 18,
                    opacity: 0.12,
                )
                rosette(
                    center: CGPoint(x: size.width * 0.12, y: size.height * 0.22),
                    spacing: compact ? 11 : 15,
                    opacity: 0.08,
                )
            }

            Image(systemName: style.symbolName)
                .font(.system(
                    size: compact
                        ? UIConstants.Size.stampWatermarkCompact
                        : UIConstants.Size.stampWatermark,
                ))
                .foregroundStyle(style.tint.opacity(0.08))
                .rotationEffect(.degrees(-14))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .offset(
                    x: compact ? UIConstants.Spacings.large : UIConstants.Spacings.xxxLarge,
                    y: compact ? UIConstants.Spacings.regular : UIConstants.Spacings.large,
                )
        }
        .clipShape(cardShape)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// A layered, official-looking frame: a heavy solid outer line, a thin solid
    /// line, a ring of perforation dots (Primary cards only), and a dashed inner
    /// line — like the engraved, perforated edge of a passport page.
    private var stampFrame: some View {
        ZStack {
            cardShape
                .strokeBorder(style.tint.opacity(0.6), lineWidth: compact ? 2.5 : 3.5)
            cardShape
                .inset(by: UIConstants.Spacings.small)
                .strokeBorder(style.tint.opacity(0.35), lineWidth: 1)
            if !compact {
                cardShape
                    .inset(by: UIConstants.Spacings.large)
                    .strokeBorder(
                        style.tint.opacity(0.45),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [0.01, 6]),
                    )
            }
            cardShape
                .inset(by: compact ? UIConstants.Spacings.large : UIConstants.Spacings.xxLarge)
                .strokeBorder(
                    style.tint.opacity(0.4),
                    style: StrokeStyle(lineWidth: 1, dash: [5, 4]),
                )
        }
        .allowsHitTesting(false)
    }

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: compact ? UIConstants.Spacings.regular : UIConstants.Spacings.xxLarge,
        ) {
            HStack(spacing: UIConstants.Spacings.large) {
                Text(style.emoji)
                    .font(compact ? .title2 : .largeTitle)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: UIConstants.Spacings.xxSmall) {
                    Text(regionDays.region.localizedName)
                        .font(.system(compact ? .headline : .title3, design: .serif)
                            .weight(.semibold))
                        .textCase(.uppercase)
                        .tracking(compact ? 1 : 1.5)
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

            HStack(alignment: .firstTextBaseline, spacing: UIConstants.Spacings.small) {
                Text(regionDays.days, format: .number)
                    .font(
                        compact
                            ? .system(.title, design: .rounded, weight: .bold)
                            : .system(
                                size: UIConstants.Size.heroNumberFontSize,
                                weight: .bold,
                                design: .rounded,
                            ),
                    )
                    .contentTransition(.numericText())
                    .foregroundStyle(style.tint)
                Text(localized: .common.dayUnit(regionDays.days))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Capsule()
                .fill(.quaternary)
                .frame(height: UIConstants.Size.progressBarHeight)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(style.tint.gradient)
                            .frame(width: proxy.size.width * fraction)
                    }
                }
                .frame(height: UIConstants.Size.progressBarHeight)
                .accessibilityHidden(true)
        }
        .padding(compact ? UIConstants.Padding.compactCard : UIConstants.Padding.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { stampPaper }
        .glassEffect(.regular.tint(style.tint.opacity(0.18)), in: cardShape)
        .holographicSheen(
            roll: tilt?.roll ?? 0,
            pitch: tilt?.pitch ?? 0,
            in: cardShape,
            tint: .white,
            intensity: compact ? 0.5 : 1,
        )
        .overlay { stampFrame }
        .clipShape(cardShape)
        .shadow(
            color: style.tint.opacity(compact ? 0.55 : 0.75),
            radius: compact
                ? UIConstants.Shadow.cardGlowRadiusCompact
                : UIConstants.Shadow.cardGlowRadius,
        )
        .shadow(
            color: style.tint.opacity(compact ? 0.4 : 0.6),
            radius: compact ? UIConstants.Shadow.cardRadiusCompact : UIConstants.Shadow.cardRadius,
            y: compact ? UIConstants.Shadow.cardOffsetYCompact : UIConstants.Shadow.cardOffsetY,
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            .common.regionDaysAccessibility(
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
                compact: true,
                year: 2026,
            )
        }
        .padding()
    }
#endif
