#if DEBUG
    import SnapshotKit
    import SwiftUI

    /// Builds a ``SnapshotCase`` whose content is seeded with `whereBroadwayRoot()`,
    /// so WhereUI views resolve trait-aware `WhereStylesheet` tokens under snapshot
    /// (and preview cutsheet) capture without each author repeating the root
    /// wrapper. Use this instead of `SnapshotCase(...)` directly when authoring
    /// WhereUI ``SnapshotProviding`` conformances.
    ///
    /// Readiness hooks pass through to ``SnapshotCase``. `onReadyToMeasure`
    /// prepares size-changing state before measurement. `onReadyToSnapshot`
    /// runs after content settles; capture then settles its effects.
    /// Use these hooks for readiness that pixel stability alone cannot prove.
    @MainActor
    public func whereSnapshot(
        name: String,
        configurations: [SnapshotConfiguration],
        measurementReadiness: SnapshotMeasurementReadiness = .sameAsCapture,
        onReadyToMeasure: (@MainActor () async -> Void)? = nil,
        settle: SnapshotSettle = .settled,
        onReadyToSnapshot: (@MainActor () async -> Void)? = nil,
        @ViewBuilder content: @escaping @MainActor () -> some View,
    ) -> SnapshotCase {
        SnapshotCase(
            name: name,
            configurations: configurations,
            measurementReadiness: measurementReadiness,
            onReadyToMeasure: onReadyToMeasure,
            settle: settle,
            onReadyToSnapshot: onReadyToSnapshot,
        ) {
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
