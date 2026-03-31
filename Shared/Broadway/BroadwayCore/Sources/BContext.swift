//
//  BContext.swift
//  BroadwayCore
//
//  Created by Kyle Van Essen on 3/3/26.
//

import Foundation

/// The root environment container that flows through the view hierarchy,
/// carrying the current ``BTraits``, ``BThemes``, and the lazily-populated
/// ``BStylesheets`` cache. Updating `traits` or `themes` replaces the
/// stylesheet cache so subsequent lookups produce fresh instances.
public struct BContext: Equatable, Sendable {
    public init(traits: BTraits = .init(), themes: BThemes = .init()) {
        self.traits = traits
        self.themes = themes
        stylesheets = BStylesheets(config: .init(traits: traits, themes: themes))
    }

    /// The current trait values (accessibility, size class, etc.).
    public var traits: BTraits {
        didSet {
            stylesheets.traits = traits
        }
    }

    /// The current theme values.
    @CopyOnWrite public var themes: BThemes {
        didSet {
            stylesheets.themes = themes
        }
    }

    /// Lazily-populated stylesheet cache, scoped to the current traits and themes.
    @CopyOnWrite public private(set) var stylesheets: BStylesheets
}
