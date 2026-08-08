@_spi(Testing) import SnapshotKitTesting
import SwiftUI
import TestHostSupport
import Testing
import UIKit
@testable import WhereUI

/// End-to-end guard that the capture flag survives the whole write→read path
/// this bundle depends on: `SnapshotKitTesting` sets `SnapshotCaptureTrait`
/// via `traitOverrides` on the captured view controller, and WhereUI's
/// stand-ins (`MotionIsStatic`, `RegionMapView`, `SnapshotDatePickerStandIn`)
/// read `\.isCapturingSnapshot` from the SwiftUI environment — a type-keyed
/// lookup that silently returns the default, never an error, if the two sides
/// ever stop resolving to the same trait.
///
/// Two things could break that, and this test catches both. UIKit could stop
/// propagating the override across the `UIHostingController` boundary; or the
/// linker could stop coalescing the `SnapshotKit` this bundle gets via
/// `SnapshotKitTesting` with the one it gets via WhereUI, splitting the trait
/// into two type metadata records (the root `AGENTS.md` "Targets" hazard — not
/// how this bundle links today, see the `Project.swift` comment, but nothing
/// in the build guarantees it stays that way).
///
/// So it probes a **WhereUI-defined** view through the real pipeline rather
/// than a local one: `SnapshotCaptureFlagTests` already covers a probe view
/// compiled into `SnapshotKitTesting`'s own bundle, which by construction
/// can't exercise either failure.
@MainActor
struct SnapshotCaptureFlagProbeTests {
    @Test func whereUIViewsReadTheCaptureFlagDuringCapture() async throws {
        try waitFor { hostKeyWindow() != nil }
        let host = UIHostingController(
            rootView: SnapshotCaptureFlagProbe().frame(width: 100, height: 100),
        )
        host.view.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        let image = try await renderSnapshotImage(
            of: host,
            named: "whereui-capture-flag-probe",
            safeAreaInsets: .zero,
        )
        let center = image.probePixel(atUnitPoint: CGPoint(x: 0.5, y: 0.5))
        #expect(center.green > 0.5)
        #expect(center.red < 0.5)
    }
}
