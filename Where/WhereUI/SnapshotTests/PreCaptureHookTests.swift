import Observation
import SnapshotKitTesting
import SwiftUI
import TestHostSupport
import Testing
import UIKit

/// Regression guard for the pre-capture hook (`onReadyToSnapshot`): it must run
/// only after the content has settled (so a hook that focuses a field or
/// presents state acts on loaded content, not a placeholder), and its effects
/// must be settled into the captured image. The probe renders red until its
/// `.task` fires (blue), and green only once the hook flips it — so a green
/// capture proves both the hook ran and its effect committed, and the hook
/// itself records whether it saw the settled (post-`.task`) state.
@MainActor
struct PreCaptureHookTests {
    @Test func hookRunsAfterSettleAndItsEffectIsCaptured() async throws {
        try waitFor { hostKeyWindow() != nil }
        let model = HookProbeModel()
        let host = UIHostingController(rootView: HookProbeView(model: model))
        host.view.frame = CGRect(x: 0, y: 0, width: 100, height: 100)

        var hookSawSettledContent = false
        let image = await renderSnapshotImage(
            of: host,
            safeAreaInsets: .zero,
            onReadyToSnapshot: {
                hookSawSettledContent = model.taskFired
                model.hookFired = true
            },
        )

        #expect(hookSawSettledContent, "the settle phase must complete before the hook runs")
        let center = image.probePixel(atUnitPoint: CGPoint(x: 0.5, y: 0.5))
        #expect(center.green > 0.5)
        #expect(center.red < 0.5)
        #expect(center.blue < 0.5)
    }
}

@Observable
private final class HookProbeModel {
    var taskFired = false
    var hookFired = false
}

private struct HookProbeView: View {
    let model: HookProbeModel

    var body: some View {
        color
            .frame(width: 100, height: 100)
            .task { model.taskFired = true }
    }

    private var color: Color {
        if model.hookFired {
            .green
        } else if model.taskFired {
            .blue
        } else {
            .red
        }
    }
}
