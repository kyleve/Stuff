@_spi(Testing) import SnapshotKitTesting
import SwiftUI
import TestHostSupport
import Testing
import UIKit

/// Regression guard for `\.isCapturingSnapshot`: the pipeline overrides
/// `SnapshotCaptureTrait` on the captured controller, and the trait-bridged
/// environment key must surface it to the hosted SwiftUI content — through the
/// hosting-controller boundary and the pipeline's re-hosting. The probe renders
/// red unless it reads the flag as `true`; a green capture proves the flag
/// crossed the pipeline into the SwiftUI environment.
///
/// This probe view is compiled into *this bundle* — the same image as the
/// pipeline — so it can't detect the flag splitting across the WhereUI
/// framework boundary; `SnapshotCaptureFlagProbeTests` covers that side with a
/// WhereUI-defined probe.
@MainActor
struct SnapshotCaptureFlagTests {
    @Test func viewsReadTheCaptureFlagDuringCapture() async throws {
        try waitFor { hostKeyWindow() != nil }
        let host = UIHostingController(rootView: CaptureFlagProbeView())
        host.view.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        let image = await renderSnapshotImage(
            of: host,
            named: "capture-flag-probe",
            safeAreaInsets: .zero,
        )
        let center = image.probePixel(atUnitPoint: CGPoint(x: 0.5, y: 0.5))
        #expect(center.green > 0.5)
        #expect(center.red < 0.5)
    }
}

private struct CaptureFlagProbeView: View {
    @Environment(\.isCapturingSnapshot) private var isCapturingSnapshot

    var body: some View {
        (isCapturingSnapshot ? Color.green : Color.red)
            .frame(width: 100, height: 100)
    }
}
