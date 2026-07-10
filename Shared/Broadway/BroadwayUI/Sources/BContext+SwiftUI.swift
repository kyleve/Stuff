//
//  BContext+SwiftUI.swift
//  BroadwayUI
//

import BroadwayCore
import SwiftUI
import UIKit

// MARK: - UIKit ↔ SwiftUI Bridging

/// Bridges ``BContext`` between UIKit's trait system and SwiftUI's
/// environment so that `@Environment(\.bContext)` automatically reads
/// from `UITraitCollection` and writes back via `traitOverrides`.
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

extension EnvironmentValues {
    /// The Broadway environment container, automatically bridged from the
    /// nearest UIKit ancestor's `UITraitCollection`.
    public var bContext: BContext {
        get { self[BContextEnvironmentKey.self] }
        set { self[BContextEnvironmentKey.self] = newValue }
    }
}
