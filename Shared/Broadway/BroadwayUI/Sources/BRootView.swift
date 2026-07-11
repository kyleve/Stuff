//
//  BRootView.swift
//  BroadwayUI
//

import BroadwayCore
import SwiftUI

/// The SwiftUI-native counterpart to ``BRootViewController``: seeds a root
/// ``BContext`` from the live system traits (color scheme, Dynamic Type,
/// accessibility) plus the given `themes`, and injects it into the environment
/// so descendants read it via `@Environment(\.bContext)`.
///
/// Where the UIKit root drives a ``BTraitsObserver``, this relies on SwiftUI:
/// re-evaluating `body` when `@Environment(\.colorScheme)` /
/// `@Environment(\.dynamicTypeSize)` change rebuilds the context, and a `.task`
/// mirrors live ``BAccessibility`` changes into state. Unlike the UIKit root, it
/// also accepts `themes`, so an app can seed its palette/typography choices at
/// the root.
public struct BRootView<Content: View>: View {
    private let themes: BThemes
    private let content: Content

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var accessibility: BAccessibility = .current()

    public init(themes: BThemes = .init(), @ViewBuilder content: () -> Content) {
        self.themes = themes
        self.content = content()
    }

    public var body: some View {
        content
            .environment(\.bContext, BRootContext.make(
                colorScheme: colorScheme,
                dynamicTypeSize: dynamicTypeSize,
                accessibility: accessibility,
                themes: themes,
            ))
            .task {
                // Re-snapshot on (re)appear, then mirror live changes until the
                // task is cancelled (which tears the observer down).
                accessibility = .current()
                for await snapshot in BAccessibility.changes() {
                    accessibility = snapshot
                }
            }
    }
}

extension View {
    /// Wraps this view in a ``BRootView`` that seeds a root ``BContext`` from the
    /// live system traits and `themes`, then injects it into the environment.
    public func broadwayRoot(themes: BThemes = .init()) -> some View {
        BRootView(themes: themes) { self }
    }
}

/// Builds the root ``BContext`` for ``BRootView`` from SwiftUI-observable system
/// inputs. Factored out so the trait mapping is unit-testable without a hosting
/// controller.
enum BRootContext {
    @MainActor
    static func make(
        colorScheme: ColorScheme,
        dynamicTypeSize: DynamicTypeSize,
        accessibility: BAccessibility,
        themes: BThemes,
    ) -> BContext {
        var traits = BTraits.system
        traits.mode = BMode(colorScheme)
        traits.contentSizeCategory = BContentSizeCategory(dynamicTypeSize)
        traits.accessibility = accessibility
        return BContext(traits: traits, themes: themes)
    }
}
