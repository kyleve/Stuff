import SFSafeSymbols
#if DEBUG
    import SnapshotKit
    import SwiftUI

    /// DEBUG-only motion workbench for the ranked card container. Its controls
    /// are session-local and never modify Card Designer drafts or production.
    struct RankingAnimationLabView: View {
        @State private var model = RankingAnimationLabModel()
        @State private var motion = WhereStylesheet.LocationCardStackStyle.OvertakeMotion.standard
        @State private var isPreviewVisible = true
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        private var previewMotion: WhereStylesheet.LocationCardStackStyle.OvertakeMotion {
            reduceMotion ? .reducedMotion : motion
        }

        var body: some View {
            Form {
                Section {
                    RankingAnimationPreview(
                        model: model,
                        motion: previewMotion,
                        isVisible: isPreviewVisible,
                    )

                    Button(action: model.playNextOvertake) {
                        Label(
                            String(localized: .rankingAnimationPlay),
                            systemSymbol: .playFill,
                        )
                    }
                } header: {
                    Text(String(localized: .rankingAnimationPreview))
                } footer: {
                    Text(String(localized: .rankingAnimationDelayFooter))
                }

                RankingAnimationControls(motion: $motion, reset: resetMotion)
            }
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
        static var snapshots: [SnapshotCase] {
            whereSnapshot(
                name: "Default",
                configurations: .fullContentPhoneLightDark,
                measurementReadiness: .immediate,
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
#endif
