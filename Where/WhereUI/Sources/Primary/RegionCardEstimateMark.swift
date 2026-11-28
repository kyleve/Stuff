import SwiftUI
import WhereCore

struct RegionCardEstimateMark: View {
    let estimatedDays: DayBounds
    let securityPrintTint: Color
    let style: WhereStylesheet.CardStyles.EstimateSticker
    let transition: WhereStylesheet.CardStyles.DayCountStyle

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let scale = style.scale
        VStack(spacing: stylesheet.spacing.xxSmall * scale) {
            Text(.locationCardEstimateLabel)
                .font(style.labelTypography.font.scaled(by: scale))
                .textCase(.uppercase)
            Text(WhereFormat.dayCount(estimatedDays))
                .font(style.valueTypography.font.scaled(by: scale))
                .monospacedDigit()
                .contentTransition(estimatedDays.isExact ? transition
                    .transition(days: estimatedDays.lower) : .opacity)
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
    }
}

#if DEBUG
    #Preview("Estimate") {
        let stylesheet = WhereStylesheet.default
        RegionCardEstimateMark(
            estimatedDays: DayBounds(lower: 269, upper: 276),
            securityPrintTint: .orange,
            style: stylesheet.card.estimateSticker,
            transition: stylesheet.card.dayCount,
        )
        .whereBroadwayRoot()
    }
#endif
