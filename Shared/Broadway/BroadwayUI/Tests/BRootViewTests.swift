import BroadwayCore
@testable import BroadwayUI
import SwiftUI
import TestHostSupport
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
            horizontalSizeClass: .regular,
            verticalSizeClass: .compact,
            accessibility: BAccessibility(isVoiceOverRunning: true),
            themes: themes,
        )

        #expect(context.traits.mode == .dark)
        #expect(context.traits.horizontalSizeClass == .regular)
        #expect(context.traits.verticalSizeClass == .compact)
        #expect(context.traits.contentSizeCategory == .accessibilityExtraLarge)
        #expect(context.traits.accessibility == BAccessibility(isVoiceOverRunning: true))
        #expect(context.themes[Marker.self] == .b)
    }
}

@MainActor
struct BRootViewHostingTests {
    @Test("A mounted root follows repeated size-class changes without replacing content")
    func followsResizing() throws {
        let box = ContextBox()
        let host = UIHostingController(rootView: BRootView { ContextProbe(box: box) })
        try show(host) { controller in
            for sizeClass in [UIUserInterfaceSizeClass.compact, .regular, .compact] {
                controller.traitOverrides.horizontalSizeClass = sizeClass
                controller.traitOverrides.verticalSizeClass = .regular
                try waitFor {
                    box.value?.traits.horizontalSizeClass == BHorizontalSizeClass(sizeClass)
                        && box.value?.traits.verticalSizeClass == .regular
                }
            }
        }
    }

    @Test("Root injects its themes into the descendant environment")
    func injectsThemes() throws {
        var themes = BThemes()
        themes[Marker.self] = .b

        let box = ContextBox()
        let host = UIHostingController(
            rootView: BRootView(themes: themes) { ContextProbe(box: box) },
        )

        try show(host) { _ in
            // `BRootView` injects the context through the pure-SwiftUI key, which
            // propagates synchronously, so a one-shot capture reads it correctly.
            try waitFor { box.value != nil }
            #expect(box.value?.themes[Marker.self] == .b)
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
        Color.clear.onChange(of: context, initial: true) { _, value in box.value = value }
    }
}
