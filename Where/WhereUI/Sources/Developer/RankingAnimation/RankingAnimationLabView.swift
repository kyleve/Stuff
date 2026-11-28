#if DEBUG
    import SFSafeSymbols
    import SnapshotKit
    import SwiftUI

    /// DEBUG-only motion workbench for the ranked card container. Its controls
    /// are session-local and never modify Card Designer drafts or production.
    struct RankingAnimationLabView: View {
        @State private var model = RankingAnimationLabModel()
        @State private var motion = WhereStylesheet.LocationCardStackStyle.OvertakeMotion.standard
        @State private var isPreviewVisible = true
        /// The session-local draft is unavailable to slicing; accessibility overrides its live
        /// motion.
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        private var previewMotion: WhereStylesheet.LocationCardStackStyle.OvertakeMotion {
            reduceMotion ? .reducedMotion : motion
        }

        var body: some View {
            Form {
                RankingAnimationPreviewSection(
                    model: model,
                    motion: previewMotion,
                    isVisible: isPreviewVisible,
                )

                RankingAnimationControls(motion: $motion, reset: resetMotion)
            }
            // Keep settled Form clipping unchanged, but let every tunable arc,
            // scale, and rotation remain visible during the live crossing.
            .scrollClipDisabled(model.presentation.isSpatialOvertakeActive)
            .navigationTitle(String(localized: .rankingAnimationTitle))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { isPreviewVisible = true }
            .onDisappear { isPreviewVisible = false }
        }

        private func resetMotion() {
            motion = .standard
        }
    }

    extension RankingAnimationLabView: SnapshotProviding {
        /// The raised floor outlasts native navigation glass's quiet-start adaptation.
        static var snapshots: [SnapshotCase] {
            whereSnapshot(
                name: "Default",
                configurations: .fullContentPhoneLightDark,
                measurementReadiness: .immediate,
                settle: .settledAtLeast(minDuration: 1.0),
            ) {
                NavigationStack {
                    RankingAnimationLabView()
                }
            }
        }
    }

    #Preview {
        RankingAnimationLabView.snapshotPreviews
    }

    extension RankingAnimationLabView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.hosted(
            RankingAnimationLabView.self,
            title: "Ranking Animation Lab",
        ) { _ in
            RankingAnimationLabView()
        }
    }

    private struct RankingOvertakePlayButton: View {
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Label(
                    String(localized: .rankingAnimationPlay),
                    systemSymbol: .playFill,
                )
            }
        }
    }

    private struct RankingAnimationPreviewSection: View {
        let model: RankingAnimationLabModel
        let motion: WhereStylesheet.LocationCardStackStyle.OvertakeMotion
        let isVisible: Bool

        var body: some View {
            Section {
                RankingAnimationPreview(
                    model: model,
                    motion: motion,
                    isVisible: isVisible,
                )

                RankingOvertakePlayButton(action: model.playNextOvertake)
            } header: {
                Text(String(localized: .rankingAnimationPreview))
            } footer: {
                Text(String(localized: .rankingAnimationDelayFooter))
            }
        }
    }

    /// The production ranked-card stack stripped only of navigation destinations
    /// so the lab can replay its real delay and overtake treatment in place.
    private struct RankingAnimationPreview: View {
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
                    RankingAnimationRegionCard(item: item, model: model, motion: motion)
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

    private struct RankingAnimationRegionCard: View {
        let item: RegionDays
        let model: RankingAnimationLabModel
        let motion: WhereStylesheet.LocationCardStackStyle.OvertakeMotion

        var body: some View {
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
#endif
