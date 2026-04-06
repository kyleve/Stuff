//
//  BContext+UITraits.swift
//  BroadwayCore
//

import UIKit

/// Bridges ``BContext`` into UIKit's trait system so that it propagates
/// automatically through the view-controller and view hierarchy.
public struct BContextTrait: UITraitDefinition {
    public static let defaultValue = BContext()
}

extension UITraitCollection {
    /// The Broadway environment container carrying traits, themes,
    /// and the stylesheet cache. Inherited from the nearest ancestor
    /// that sets one; returns a default empty context otherwise.
    public var bContext: BContext {
        self[BContextTrait.self]
    }
}

extension UIMutableTraits {
    /// Gets or sets the ``BContext`` for this mutable traits collection.
    public var bContext: BContext {
        get { self[BContextTrait.self] }
        set { self[BContextTrait.self] = newValue }
    }
}
