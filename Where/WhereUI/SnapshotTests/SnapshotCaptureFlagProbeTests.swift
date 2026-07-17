import SnapshotKitTesting
import SwiftUI
import TestHostSupport
import Testing
import UIKit
@testable import WhereUI

/// Cross-boundary regression guard for the duplicate `SnapshotKit` embed:
/// this bundle statically links `SnapshotKitTesting`, which embeds a second
/// copy of `SnapshotKit` alongside the one inside the WhereUI dynamic
/// framework (see the WhereUISnapshotTests comment in `Project.swift`). The
/// pipeline writes `SnapshotCaptureTrait` through the bundle's copy while
/// WhereUI's stand-ins (`MotionIsStatic`, `RegionMapView`,
/// `SnapshotDatePickerStandIn`) read `\.isCapturingSnapshot` through WhereUI's
/// copy — a type-keyed lookup that silently returns the default if the copies
/// ever split into separate type metadata (the root `AGENTS.md` "Targets"
/// hazard). So, like `WhereStylesheetTests.resolvesTraitAwareTokensFromTheBroadwayRoot`
/// for Broadway, this probes a **WhereUI-defined** view through the pipeline:
/// a green capture proves the write and the read resolved against the same
/// logical trait across the framework boundary.
/// (`SnapshotCaptureFlagTests` covers the same-image side — a probe view
/// compiled into this bundle — and cannot detect a cross-boundary split.)
@MainActor
struct SnapshotCaptureFlagProbeTests {
    @Test func whereUIViewsReadTheCaptureFlagDuringCapture() async throws {
        try waitFor { hostKeyWindow() != nil }
        let host = UIHostingController(
            rootView: SnapshotCaptureFlagProbe().frame(width: 100, height: 100),
        )
        host.view.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        let image = await renderSnapshotImage(of: host, safeAreaInsets: .zero)
        let center = image.probePixel(atUnitPoint: CGPoint(x: 0.5, y: 0.5))
        #expect(center.green > 0.5)
        #expect(center.red < 0.5)
    }
}
