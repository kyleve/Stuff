import SFSafeSymbols
import SwiftUI

struct RegionCardLabels: View {
    let name: String
    let caption: String?
    let places: String?
    let card: WhereStylesheet.CardStyle
    let contentTint: Color
    let nameOpacity: Double
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        VStack(alignment: .leading, spacing: stylesheet.spacing.xxSmall) {
            Text(name)
                .font(card.regionNameTypography.font)
                .tracking(card.regionNameTracking)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .allowsTightening(true)
                .minimumScaleFactor(0.7)
                .foregroundStyle(contentTint)
                .opacity(card.paper == nil ? nameOpacity : 1)
            if let caption {
                Text(caption)
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(1)
                    .foregroundStyle(card.paper == nil
                        ? AnyShapeStyle(.secondary)
                        : AnyShapeStyle(contentTint))
            }
            if let places {
                Label(places, systemSymbol: .mappinAndEllipse)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(contentTint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#if DEBUG
    #Preview("Region card") {
        RegionSummaryCard(
            regionDays: RegionDays(region: .california, days: 148),
            caption: "Home base",
            year: 2026,
        )
        .whereBroadwayRoot()
    }
#endif
