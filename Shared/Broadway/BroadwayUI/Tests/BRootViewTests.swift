import BroadwayCore
import BroadwayTesting
@testable import BroadwayUI
import SwiftUI
import Testing
import UIKit

private enum Marker: String, BTheme {
    static let defaultValue: Self = .a
    case a, b
}

@MainActor
struct BRootContextTests {
    @Test("make maps SwiftUI system inputs into the context traits and themes")
    func mapsSystemInputs() {
        var themes = BThemes()
        themes[Marker.self] = .b

        let context = BRootContext.make(
            colorScheme: .dark,
            dynamicTypeSize: .accessibility3,
            accessibility: BAccessibility(isVoiceOverRunning: true),
            themes: themes,
        )

        #expect(context.traits.mode == .dark)
        #expect(context.traits.contentSizeCategory == .accessibilityExtraLarge)
        #expect(context.traits.accessibility == BAccessibility(isVoiceOverRunning: true))
        #expect(context.themes[Marker.self] == .b)
    }
}

@MainActor
struct BRootViewHostingTests {
    @Test("Root injects its themes into the descendant environment")
    func injectsThemes() throws {
        var themes = BThemes()
        themes[Marker.self] = .b

        let box = ContextBox()
        let host = UIHostingController(
            rootView: BRootView(themes: themes) { ContextProbe(box: box) },
        )

        try show(host) { _ in
            // Poll for the injected themes rather than snapshotting the first
            // frame: the context bridges through UIKit traits, so it can land a
            // render after the probe first appears.
            try waitFor { box.value?.themes[Marker.self] == .b }
            #expect(box.value?.traits.accessibility == BAccessibility.current())
        }
    }
}

private final class ContextBox {
    var value: BContext?
}

private struct ContextProbe: View {
    let box: ContextBox

    @Environment(\.bContext) private var context

    var body: some View {
        // Capture on every render (not a one-shot `onAppear`) so a bridged
        // context that arrives after first appearance is observed.
        Color.clear.onChange(of: context, initial: true) { _, newValue in
            box.value = newValue
        }
    }
}
