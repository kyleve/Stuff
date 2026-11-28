import SwiftUI
import WhereCore

/// Pairs a primary card's recorded total with its annual estimate, rendered as
/// a compact visa-style endorsement that restacks when horizontal room runs out.
struct LocationCardEstimateSticker: View {
    let recordedDays: Int
    let estimatedDays: DayBounds
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

        let sticker = RegionCardEstimateMark(
            estimatedDays: estimatedDays,
            securityPrintTint: securityPrintTint,
            style: style,
            transition: transition,
        )

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
            estimatedDays: DayBounds(lower: 269, upper: 276),
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
