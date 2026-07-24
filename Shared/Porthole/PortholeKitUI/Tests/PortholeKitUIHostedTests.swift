import BroadwayCore
import BroadwayUI
import PortholeKit
@testable import PortholeKitUI
import SwiftUI
import TestHostSupport
import Testing
import UIKit

/// Covers the PortholeKitUI Broadway glue and that its views render — the
/// trait-aware slice resolves across the PortholeKitUI↔BroadwayUI boundary, and
/// `PortholePairingView` hosts without crashing.
@MainActor
struct PortholeKitUIHostedTests {
    @Test func resolvesTraitAwareTokensFromTheBroadwayRoot() throws {
        let box = StylesheetProbeBox()
        let host = UIHostingController(
            rootView: StylesheetProbe(box: box)
                .bContentSizeCategory(.accessibilityLarge)
                .portholeBroadwayRoot(),
        )
        try show(host) { _ in
            try waitFor { box.digitTracking == 10 }
        }
    }

    @Test func pairingViewHostsWithoutCrashing() throws {
        let porthole = Porthole(configuration: PortholeConfiguration(appName: "TestApp"))
        let host = UIHostingController(rootView: PortholePairingView(porthole: porthole))
        try show(host) { controller in
            try waitFor { controller.view.window != nil }
        }
    }
}

private final class StylesheetProbeBox {
    var digitTracking: CGFloat?
}

private struct StylesheetProbe: View {
    let box: StylesheetProbeBox
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        Color.clear.onAppear { box.digitTracking = stylesheet.code.digitTracking }
    }
}
