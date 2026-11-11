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
    @Test func fullContentNavigationPropagatesIndependentContentInsets() async throws {
        try waitFor { hostKeyWindow() != nil }
        let screen = NavigationStack {
            List { Text("History") }
                .searchable(text: .constant(""))
                .navigationTitle("History")
                .navigationBarTitleDisplayMode(.inline)
        }
        let host = UIHostingController(rootView: screen)
        host.traitOverrides.horizontalSizeClass = .compact
        host.traitOverrides.userInterfaceIdiom = .phone
        host.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        let insets = UIEdgeInsets(top: 37, left: 11, bottom: 59, right: 29)
        _ = try await renderSnapshotImage(
            of: host,
            named: "native-asymmetric-insets",
            sizing: .intrinsic(width: 402, minimumHeight: 874),
            safeAreaInsets: insets,
            onReadyToSnapshot: {
                @MainActor func navigationControllers(in controller: UIViewController)
                    -> [UINavigationController]
                {
                    if let navigation = controller as? UINavigationController { return [navigation]
                    }
                    return controller.children.flatMap { navigationControllers(in: $0) }
                }
                let controllers = navigationControllers(in: host)
                #expect(!controllers.isEmpty)
                for controller in controllers {
                    let bar = controller.navigationBar
                    let frame = bar.convert(bar.bounds, to: host.view)
                    #expect(frame.minY >= insets.top)
                    #expect(frame.minY <= insets.top + 8)
                    #expect(controller.view.safeAreaInsets.left == insets.left)
                    #expect(controller.view.safeAreaInsets.right == insets.right)
                    #expect(controller.view.safeAreaInsets.bottom >= insets.bottom)
                }
                @MainActor func fields(in view: UIView) -> [UITextField] {
                    if let field = view as? UITextField { return [field] }
                    return view.subviews.flatMap { fields(in: $0) }
                }
                let searchFields = fields(in: host.view)
                #expect(!searchFields.isEmpty)
                for field in searchFields {
                    let frame = field.convert(field.bounds, to: host.view)
                    // Floating search chrome uses system geometry rather than
                    // additional content insets. Its placement within native
                    // reserved regions requires a native-device check.
                    #expect(host.view.bounds.contains(frame))
                    #expect(frame.maxY >= host.view.bounds.maxY - 120)
                }
            },
        )
    }

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
