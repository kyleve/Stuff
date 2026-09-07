@_spi(Testing) import SnapshotKitTesting
import SwiftUI
import TestHostSupport
import Testing
import UIKit

/// Regression guard for `SafeAreaInsetsSwizzling`. The swizzle zeroes the
/// captured **root**'s `safeAreaInsets` — decoupling the image from the
/// simulator's notch/home indicator — so a safe-area-respecting view reaches the
/// top edge instead of being pushed down by the device insets
/// (`zeroedRootLeavesNoDeviceInset`). It must do that *without* erasing
/// contributions layered mid-tree: a `safeAreaInset` bar (the same mechanism a
/// nav bar / toolbar uses) still composes on top of the zeroed base, so the bar
/// sits flush at the top and its content lays out below it — not crammed under
/// it and not offset by the device insets (`safeAreaInsetBarComposesOnTheZeroedRoot`).
/// An earlier design that returned the override for *every* in-tree view erased
/// such contributions; this pins that it doesn't.
@MainActor
struct SafeAreaCompositionTests {
    @Test func zeroedRootLeavesNoDeviceInset() async throws {
        try waitFor { hostKeyWindow() != nil }
        let host = UIHostingController(rootView: Color.red)
        host.view.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        let image = try await renderSnapshotImage(
            of: host,
            named: "zeroed-root-probe",
            safeAreaInsets: .zero,
        )

        // A safe-area-respecting fill reaches the very top: the device's real
        // top inset was zeroed at the root rather than leaking into the image.
        let top = image.probePixel(atUnitPoint: CGPoint(x: 0.5, y: 0.05))
        #expect(top.red > 0.5)
        #expect(top.green < 0.5)
    }

    @Test func safeAreaInsetBarComposesOnTheZeroedRoot() async throws {
        try waitFor { hostKeyWindow() != nil }
        let host = UIHostingController(rootView: BarProbeView())
        host.view.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        let image = try await renderSnapshotImage(
            of: host,
            named: "safe-area-bar-probe",
            safeAreaInsets: .zero,
        )

        // The 30pt bar sits flush at the top (not offset by device insets) —
        // the interior contribution composed on the zeroed base.
        let inBar = image.probePixel(atUnitPoint: CGPoint(x: 0.5, y: 0.15))
        #expect(inBar.green > 0.5)
        #expect(inBar.red < 0.5)

        // Below the bar: the content the bar inset, still present rather than
        // crammed under the bar.
        let belowBar = image.probePixel(atUnitPoint: CGPoint(x: 0.5, y: 0.6))
        #expect(belowBar.red > 0.5)
        #expect(belowBar.green < 0.5)
    }
}

/// A red content pane with a 30pt green `safeAreaInset` bar pinned to the top —
/// the bar's contribution must compose on top of the captured root's zeroed
/// safe area.
private struct BarProbeView: View {
    var body: some View {
        Color.red
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.green.frame(height: 30)
            }
    }
}
