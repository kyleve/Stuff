#if DEBUG
    import SnapshotKit
    import SwiftUI

    /// Test-only cross-boundary probe for `\.isCapturingSnapshot`: green when the
    /// flag reads `true`, red otherwise.
    ///
    /// This view exists to be *compiled into WhereUI* and
    /// pixel-probed from the snapshot bundle
    /// (`WhereUISnapshotTests.SnapshotCaptureFlagProbeTests`): the bundle
    /// statically embeds a second copy of `SnapshotKit` via `SnapshotKitTesting`
    /// (see the snapshot-bundle comment in `Project.swift`), so the pipeline
    /// *writes* `SnapshotCaptureTrait` in the bundle's copy while WhereUI's
    /// stand-ins *read* `\.isCapturingSnapshot` through WhereUI's copy. If those
    /// copies ever split (the duplicate-type-metadata hazard in the root
    /// `AGENTS.md` "Targets" note), this view reads `false` during capture and the
    /// probe fails loudly — instead of every wall-clock/map-tile/motion stand-in
    /// silently reverting to nondeterministic rendering.
    struct SnapshotCaptureFlagProbe: View {
        @Environment(\.isCapturingSnapshot) private var isCapturingSnapshot

        var body: some View {
            isCapturingSnapshot ? Color.green : Color.red
        }
    }

    #Preview {
        SnapshotCaptureFlagProbe()
            .frame(width: 100, height: 100)
    }
#endif
