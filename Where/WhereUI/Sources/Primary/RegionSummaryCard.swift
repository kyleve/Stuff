import SwiftUI
import WhereCore

/// A Liquid Glass card summarizing how many days were spent in one region.
/// Used prominently on the Primary tab and (more compactly) on Elsewhere.
struct RegionSummaryCard: View {
    let regionDays: RegionDays
    var caption: String?
    var compact = false

    /// Calendar days in the year being summarized; the ambient bar is drawn as
    /// a fraction of this. Callers pass the selected year's real length
    /// (`WhereModel.daysInSelectedYear`); the default is only for previews.
    var yearLength = 365

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
                        .font(compact ? .headline : .title3.weight(.semibold))
                    if let caption {
                        Text(caption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: style.symbolName)
                    .font(compact ? .body : .title3)
                    .foregroundStyle(style.tint)
                    .accessibilityHidden(true)
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
                Text(Strings.dayUnit(regionDays.days))
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
        .glassEffect(.regular.tint(style.tint.opacity(0.18)), in: cardShape)
        .holographicSheen(
            roll: tilt?.roll ?? 0,
            pitch: tilt?.pitch ?? 0,
            in: cardShape,
            tint: .white,
            intensity: compact ? 0.5 : 1,
        )
        .overlay {
            cardShape.strokeBorder(style.tint.opacity(0.25), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            Strings.regionDaysAccessibility(
                region: regionDays.region.localizedName,
                days: regionDays.days,
            ),
        )
    }
}

#if DEBUG
    #Preview {
        VStack {
            RegionSummaryCard(
                regionDays: RegionDays(region: .california, days: 148),
                caption: "Home base",
            )
            RegionSummaryCard(
                regionDays: RegionDays(region: .newYork, days: 22),
                compact: true,
            )
        }
        .padding()
    }
#endif
