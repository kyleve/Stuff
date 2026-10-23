#if DEBUG
    import BroadwayUI
    import SnapshotKit
    import SwiftUI
    import WhereCore

    /// Primes the same injected artwork cache the live view consumes before capture.
    @MainActor
    func onboardingSnapshot(
        name: String,
        configurations: [SnapshotConfiguration],
        theme: WhereTheme = .standard,
        reduceTransparency: Bool = false,
        @ViewBuilder content: @escaping @MainActor () -> some View,
    ) -> SnapshotCase {
        let cache = RegionOutlinePathCache()
        return whereSnapshot(
            name: name,
            configurations: configurations,
            theme: theme,
            onReadyToSnapshot: {
                await PreviewSupport.loadCardArtwork(
                    for: OnboardingSampleHistory.regions,
                    cache: cache,
                )
            },
        ) {
            content()
                .environment(\.regionOutlinePathCache, cache)
                .bTraitOverrides { traits, overrides in
                    var accessibility = traits.accessibility
                    accessibility.isReduceTransparencyEnabled = reduceTransparency
                    overrides.accessibility = accessibility
                }
        }
    }

    @MainActor
    func onboardingThemeSnapshot(
        name: String,
        configurations: [SnapshotConfiguration],
        @ViewBuilder content: @escaping @MainActor () -> some View,
    ) -> SnapshotCase {
        let cache = RegionOutlinePathCache()
        return whereThemeSnapshot(
            name: name,
            configurations: configurations,
            onReadyToSnapshot: {
                await PreviewSupport.loadCardArtwork(
                    for: OnboardingSampleHistory.regions,
                    cache: cache,
                )
            },
        ) {
            content().environment(\.regionOutlinePathCache, cache)
        }
    }
#endif
