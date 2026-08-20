#if DEBUG
    import SwiftUI

    /// The production ranked-card stack stripped only of navigation destinations
    /// so the lab can replay its real delay and overtake treatment in place.
    struct RankingAnimationPreview: View {
        let model: RankingAnimationLabModel
        let motion: WhereStylesheet.LocationCardStackStyle.OvertakeMotion
        let isVisible: Bool

        @Namespace private var rankingTransition
        @Environment(\.stylesheet) private var stylesheet

        var body: some View {
            GlassEffectContainer(spacing: stylesheet.spacing.xxLarge) {
                VStack(spacing: stylesheet.spacing.xxLarge) {
                    ForEach(model.presentation.presented(model.current)) { item in
                        RegionSummaryCard(
                            regionDays: item,
                            interactive: false,
                            yearLength: 365,
                            year: RankingAnimationLabModel.year,
                        )
                        .locationCardOvertakeEffect(
                            region: item.region,
                            namespace: rankingTransition,
                            presentation: model.presentation,
                            motion: motion,
                        )
                    }
                }
            }
            .reconcilesLocationCards(
                current: model.current,
                year: RankingAnimationLabModel.year,
                isVisible: isVisible,
                presentation: model.presentation,
                motionOverride: motion,
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
