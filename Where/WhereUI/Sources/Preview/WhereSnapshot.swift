#if DEBUG
    import SnapshotKit
    import SwiftUI

    /// Builds a ``SnapshotCase`` whose content is seeded with `whereBroadwayRoot()`,
    /// so WhereUI views resolve trait-aware `WhereStylesheet` tokens under snapshot
    /// (and preview cutsheet) capture without each author repeating the root
    /// wrapper. Use this instead of `SnapshotCase(...)` directly when authoring
    /// WhereUI ``SnapshotProviding`` conformances.
    @MainActor
    public func whereSnapshot(
        name: String,
        configurations: [SnapshotConfiguration],
        @ViewBuilder content: @MainActor () -> some View,
    ) -> SnapshotCase {
        SnapshotCase(name: name, configurations: configurations) {
            content().whereBroadwayRoot()
        }
    }

    extension [SnapshotConfiguration] {
        /// Light + dark at an iPhone frame — the compact matrix for the extra
        /// states in a multi-state screen loop (the representative state carries
        /// the full ``screenDefaults``).
        static var phoneLightDark: Self {
            SnapshotConfiguration.combinations(devices: [.iPhone], colorSchemes: [.light, .dark])
        }

        /// Light + dark at the component frame — the compact matrix for the extra
        /// states in a sheet/component/widget loop.
        static var componentLightDark: Self {
            SnapshotConfiguration.combinations(colorSchemes: [.light, .dark])
        }
    }
#endif
