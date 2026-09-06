import SwiftUI

/// Pairs a primary card's recorded total with its annual estimate, rendered as
/// a compact visa-style endorsement that restacks when horizontal room runs out.
struct LocationCardEstimateSticker: View {
    let recordedDays: Int
    let estimatedDays: Int
    let regionTint: Color
    let securityPrintTint: Color
    let card: WhereStylesheet.CardStyle
    let style: WhereStylesheet.CardStyles.EstimateSticker
    let transition: WhereStylesheet.CardStyles.DayCountStyle

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let scale = style.scale
        let recorded = LocationCardDayCount(
            days: recordedDays,
            tint: regionTint,
            card: card,
            transition: transition.transition(days: recordedDays),
        )
        let sticker = VStack(spacing: stylesheet.spacing.xxSmall * scale) {
            Text(.locationCardEstimateLabel)
                .font(style.labelTypography.font.scaled(by: scale))
                .textCase(.uppercase)
            Text(WhereFormat.dayCount(estimatedDays))
                .font(style.valueTypography.font.scaled(by: scale))
                .monospacedDigit()
                .contentTransition(transition.transition(days: estimatedDays))
        }
        .foregroundStyle(securityPrintTint.opacity(style.contentOpacity))
        .padding(.horizontal, style.horizontalPadding * scale)
        .padding(.vertical, style.verticalPadding * scale)
        .background {
            RoundedRectangle(cornerRadius: style.cornerRadius * scale)
                .fill(securityPrintTint.opacity(style.fillOpacity))
        }
        .overlay {
            RoundedRectangle(cornerRadius: style.cornerRadius * scale)
                .strokeBorder(
                    securityPrintTint.opacity(style.outlineOpacity),
                    lineWidth: style.outlineWidth * scale,
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: (style.cornerRadius - style.innerInset) * scale,
                    )
                    .strokeBorder(
                        securityPrintTint.opacity(style.outlineOpacity),
                        style: StrokeStyle(
                            lineWidth: style.innerOutlineWidth * scale,
                            dash: style.innerDash.map { $0 * scale },
                        ),
                    )
                    .padding(style.innerInset * scale)
                }
        }
        .rotationEffect(.degrees(style.rotationDegrees))
        .fixedSize()

        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: stylesheet.spacing.large) {
                recorded
                Spacer(minLength: 0)
                sticker
            }
            VStack(alignment: .leading, spacing: stylesheet.spacing.medium) {
                recorded
                sticker
            }
        }
    }
}

#if DEBUG
    #Preview {
        let stylesheet = WhereStylesheet.default
        LocationCardEstimateSticker(
            recordedDays: 148,
            estimatedDays: 276,
            regionTint: .orange,
            securityPrintTint: .orange,
            card: stylesheet.card.regular,
            style: stylesheet.card.estimateSticker,
            transition: stylesheet.card.dayCount,
        )
        .padding()
        .whereBroadwayRoot()
    }
#endif
