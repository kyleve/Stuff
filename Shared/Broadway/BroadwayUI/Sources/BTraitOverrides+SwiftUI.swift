//
//  BTraitOverrides+SwiftUI.swift
//  BroadwayUI
//

import BroadwayCore
import SwiftUI

extension View {
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

    /// Overrides the ``BMode`` (light/dark) for this view's subtree.
    public func bMode(_ mode: BMode) -> some View {
        bTraitOverrides { _, overrides in overrides.mode = mode }
    }

    /// Overrides the ``BContentSizeCategory`` for this view's subtree.
    public func bContentSizeCategory(_ category: BContentSizeCategory) -> some View {
        bTraitOverrides { _, overrides in overrides.contentSizeCategory = category }
    }
}
