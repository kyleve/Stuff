//
//  BTraitOverrides+SwiftUI.swift
//  BroadwayUI
//

import BroadwayCore
import SwiftUI

extension View {
    /// Overrides the SwiftUI color scheme and Broadway mode together for this subtree.
    public func bColorScheme(_ colorScheme: ColorScheme) -> some View {
        environment(\.colorScheme, colorScheme)
            .bMode(BMode(colorScheme))
    }

    /// Sets Dynamic Type in SwiftUI and mirrors its effective value into Broadway.
    public func bDynamicTypeSize(_ size: DynamicTypeSize) -> some View {
        modifier(BDynamicTypeSizeBridge())
            .dynamicTypeSize(size)
    }

    /// Caps Dynamic Type in SwiftUI and mirrors the resulting size into Broadway.
    public func bDynamicTypeSize(upTo limit: DynamicTypeSize) -> some View {
        modifier(BDynamicTypeSizeBridge())
            .dynamicTypeSize(...limit)
    }

    /// Applies trait overrides to the ``BContext`` flowing through this
    /// view's environment. The closure receives the current resolved
    /// traits and a mutable ``BTraits/Overrides`` to modify.
    public func bTraitOverrides(
        _ apply: @escaping (BTraits, inout BTraits.Overrides) -> Void,
    ) -> some View {
        transformEnvironment(\.bContext) { context in
            apply(context.traits, &context.traitOverrides)
        }
    }

    /// Overrides Broadway mode without changing the native SwiftUI color scheme.
    public func bMode(_ mode: BMode) -> some View {
        bTraitOverrides { _, overrides in overrides.mode = mode }
    }

    /// Overrides Broadway size without changing native SwiftUI Dynamic Type.
    public func bContentSizeCategory(_ category: BContentSizeCategory) -> some View {
        bTraitOverrides { _, overrides in overrides.contentSizeCategory = category }
    }
}

/// Reads the native size after SwiftUI applies inherited ranges and scoped overrides.
private struct BDynamicTypeSizeBridge: ViewModifier {
    /// Native trait reflection is the bridge input after SwiftUI resolves size ranges.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        content.bContentSizeCategory(BContentSizeCategory(dynamicTypeSize))
    }
}
