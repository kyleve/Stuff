#if DEBUG
    import SwiftUI

    /// The production ranked-card stack stripped only of navigation destinations
    /// so the lab can replay its real delay and overtake treatment in place.
    struct RankingAnimationPreview: View {
        let model: RankingAnimationLabModel
        let motion: WhereStylesheet.LocationCardStackStyle.OvertakeMotion
        let isVisible: Bool

        @Environment(\.stylesheet) private var stylesheet

        var body: some View {
            let presentedCards = model.presentation.presented(model.current)

            LocationCardRankingStack(
                spacing: stylesheet.spacing.xxLarge,
                presentation: model.presentation,
                motion: motion,
            ) {
                ForEach(presentedCards) { item in
                    RegionSummaryCard(
                        regionDays: item,
                        interactive: false,
                        yearLength: 365,
                        year: RankingAnimationLabModel.year,
                    )
                    .locationCardOvertakeEffect(
                        region: item.region,
                        presentation: model.presentation,
                        motion: motion,
                    )
                    .locationCardRankingRegion(item.region)
                }
            }
            .reconcilesLocationCards(
                current: model.current,
                year: RankingAnimationLabModel.year,
                isVisible: isVisible,
                presentation: model.presentation,
                motion: motion,
            )
        }
    }

    #Preview {
        RankingAnimationPreview(
            model: RankingAnimationLabModel(),
            motion: .standard,
            isVisible: true,
        )
        .padding()
        .whereBroadwayRoot()
    }
#endif
