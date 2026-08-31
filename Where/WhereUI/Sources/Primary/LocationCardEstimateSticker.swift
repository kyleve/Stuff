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
        let recorded = LocationCardDayCount(
            days: recordedDays,
            tint: regionTint,
            card: card,
            transition: transition.transition(days: recordedDays),
        )
        let sticker = VStack(spacing: stylesheet.spacing.xxSmall) {
            Text(.locationCardEstimateLabel)
                .font(style.labelTypography.font)
                .textCase(.uppercase)
            Text(WhereFormat.dayCount(estimatedDays))
                .font(style.valueTypography.font)
                .monospacedDigit()
                .contentTransition(transition.transition(days: estimatedDays))
        }
        .foregroundStyle(securityPrintTint)
        .padding(.horizontal, style.horizontalPadding)
        .padding(.vertical, style.verticalPadding)
        .background {
            RoundedRectangle(cornerRadius: style.cornerRadius)
                .fill(securityPrintTint.opacity(style.fillOpacity))
        }
        .overlay {
            RoundedRectangle(cornerRadius: style.cornerRadius)
                .strokeBorder(
                    securityPrintTint.opacity(style.outlineOpacity),
                    lineWidth: style.outlineWidth,
                )
                .overlay {
                    RoundedRectangle(cornerRadius: style.cornerRadius - style.innerInset)
                        .strokeBorder(
                            securityPrintTint.opacity(style.outlineOpacity),
                            style: StrokeStyle(
                                lineWidth: style.innerOutlineWidth,
                                dash: style.innerDash,
                            ),
                        )
                        .padding(style.innerInset)
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
