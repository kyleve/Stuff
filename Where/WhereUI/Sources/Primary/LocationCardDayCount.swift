import SwiftUI

/// The primary card's recorded total, with its unit sharing the number's baseline.
struct LocationCardDayCount: View {
    let days: Int
    let tint: Color
    let card: WhereStylesheet.CardStyle
    let transition: ContentTransition

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: stylesheet.spacing.small) {
            Text(days, format: .number)
                .font(card.heroNumberTypography.font)
                .contentTransition(transition)
                .foregroundStyle(tint)
            Text(WhereFormat.dayUnit(days))
                .font(card.dayUnitTypography.font)
                .foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
    #Preview {
        LocationCardDayCount(
            days: 148,
            tint: .orange,
            card: WhereStylesheet.default.card.regular,
            transition: .numericText(value: 148),
        )
        .padding()
        .whereBroadwayRoot()
    }
#endif
