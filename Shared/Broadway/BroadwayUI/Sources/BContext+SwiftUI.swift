//
//  BContext+SwiftUI.swift
//  BroadwayUI
//

import BroadwayCore
import SwiftUI
import UIKit

// This file intentionally uses manual environment keys with a custom `bContext`
// accessor (a fallback getter `@Entry` can't express), so keep SwiftFormat from
// rewriting it into an `@Entry`.
// swiftformat:disable environmentEntry

// MARK: - UIKit ↔ SwiftUI Bridging

/// Bridges a ``BContext`` set on UIKit's trait system (e.g. by
/// ``BRootViewController``) *into* SwiftUI. This is the fallback the
/// `\.bContext` environment value reads when no SwiftUI ancestor has set one.
struct BContextEnvironmentKey: UITraitBridgedEnvironmentKey {
    static var defaultValue: BContext {
        BContextTrait.defaultValue
    }

    static func read(from traitCollection: UITraitCollection) -> BContext {
        traitCollection.bContext
    }

    static func write(to mutableTraits: inout UIMutableTraits, value: BContext) {
        mutableTraits.bContext = value
    }
}

/// A pure-SwiftUI ``BContext`` set by the SwiftUI-native surfaces
/// (``BRootView`` / `broadwayRoot(themes:)` and `bTraitOverrides`). Because it's
/// an ordinary `EnvironmentKey` — not trait-bridged — it propagates
/// synchronously through the SwiftUI tree with no `UITraitCollection`
/// round-trip. `nil` means "no SwiftUI ancestor set one", so `\.bContext` falls
/// back to the UIKit-bridged value.
private struct SwiftUIBContextKey: EnvironmentKey {
    static let defaultValue: BContext? = nil
}

extension EnvironmentValues {
    /// The Broadway environment container.
    ///
    /// A context set from SwiftUI (``BRootView`` / `broadwayRoot(themes:)` /
    /// `bTraitOverrides`) takes precedence and propagates synchronously; with no
    /// SwiftUI context set it falls back to the one bridged from the nearest
    /// UIKit ancestor's `UITraitCollection` (e.g. a ``BRootViewController``).
    ///
    /// - Note: A SwiftUI-set context is intentionally *not* written back into
    ///   the UIKit trait system, so it does not propagate into nested UIKit
    ///   views. Seed the UIKit root (``BRootViewController``) when the context
    ///   must reach UIKit descendants.
    public var bContext: BContext {
        get { self[SwiftUIBContextKey.self] ?? self[BContextEnvironmentKey.self] }
        set { self[SwiftUIBContextKey.self] = newValue }
    }
}

// swiftformat:enable environmentEntry
