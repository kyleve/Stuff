#if DEBUG
    import SnapshotKit
    import SwiftUI
    import WhereCore

    /// Builds a ``SnapshotCase`` whose content is seeded with `whereBroadwayRoot()`,
    /// so WhereUI views resolve trait-aware `WhereStylesheet` tokens under snapshot
    /// (and preview cutsheet) capture without each author repeating the root
    /// wrapper. Use this instead of `SnapshotCase(...)` directly when authoring
    /// WhereUI ``SnapshotProviding`` conformances.
    ///
    /// `onReadyToSnapshot` passes through to ``SnapshotCase``: the capture
    /// pipeline runs it after the content settles and re-settles its effects —
    /// the seam for a deterministic completion signal (e.g. awaiting a launch
    /// runner's drive) that pixel stability alone can't provide.
    @MainActor
    public func whereSnapshot(
        name: String,
        theme: WhereTheme = .alternate,
        configurations: [SnapshotConfiguration],
        measurementReadiness: SnapshotMeasurementReadiness = .sameAsCapture,
        settle: SnapshotSettle = .settled,
        onReadyToSnapshot: (@MainActor () async -> Void)? = nil,
        @ViewBuilder content: @escaping @MainActor () -> some View,
    ) -> SnapshotCase {
        SnapshotCase(
            name: name,
            configurations: configurations,
            measurementReadiness: measurementReadiness,
            settle: settle,
            onReadyToSnapshot: onReadyToSnapshot,
        ) {
            content().whereBroadwayRoot(theme: theme)
        }
    }

    extension [SnapshotConfiguration] {
        /// Light + dark at an iPhone frame — the compact matrix for the extra
        /// states in a multi-state screen loop (the representative state carries
        /// the full ``screenDefaults``).
        static var phoneLightDark: Self {
            SnapshotConfiguration.combinations(devices: [.iPhone], colorSchemes: [.light, .dark])
        }

        /// Light + dark at an intrinsic-height iPhone-width frame — the compact
        /// matrix for extra states on a full-content screen.
        static var fullContentPhoneLightDark: Self {
            SnapshotConfiguration.combinations(
                devices: [.iPhoneFullContent],
                colorSchemes: [.light, .dark],
            )
        }

        /// Light + dark at the component frame — the compact matrix for the extra
        /// states in a sheet/component/widget loop.
        static var componentLightDark: Self {
            SnapshotConfiguration.combinations(colorSchemes: [.light, .dark])
        }
    }
#endif
