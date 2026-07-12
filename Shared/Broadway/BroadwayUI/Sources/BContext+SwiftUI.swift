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

/// Bridges ``BContext`` between SwiftUI and UIKit's trait system. The
/// `\.bContext` accessor reads it as a fallback (so a UIKit-set context, e.g.
/// from ``BRootViewController``, reaches SwiftUI) and mirrors SwiftUI writes
/// into it (so a SwiftUI-set context reaches nested UIKit).
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
    /// `bTraitOverrides`) is stored in a pure-SwiftUI key so SwiftUI reads it
    /// synchronously (no `UITraitCollection` round-trip), and is *also* mirrored
    /// into the UIKit trait system so it reaches nested UIKit views. With no
    /// SwiftUI context set, it falls back to the value bridged from the nearest
    /// UIKit ancestor's `UITraitCollection` (e.g. a ``BRootViewController``).
    public var bContext: BContext {
        get { self[SwiftUIBContextKey.self] ?? self[BContextEnvironmentKey.self] }
        set {
            // Store for synchronous SwiftUI reads, and mirror into the UIKit
            // trait system so a SwiftUI-set context reaches nested UIKit views.
            self[SwiftUIBContextKey.self] = newValue
            self[BContextEnvironmentKey.self] = newValue
        }
    }
}

// swiftformat:enable environmentEntry
