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
    public init(
        traits: BTraits,
        overrides: BTraits.Overrides = .init(),
        themes: BThemes = .init(),
    ) {
        baseTraits = traits
        traitOverrides = overrides
        self.themes = themes
        stylesheets = BStylesheets(
            traits: baseTraits.merging(with: traitOverrides),
            themes: themes,
        )
    }

    init() {
        self.init(traits: BTraits())
    }

    public var traitOverrides: BTraits.Overrides {
        didSet {
            stylesheets.updateTraits(traits)
        }
    }

    public var traits: BTraits {
        baseTraits.merging(with: traitOverrides)
    }

    /// The current trait values (accessibility, size class, etc.).
    public var baseTraits: BTraits {
        didSet {
            stylesheets.updateTraits(traits)
        }
    }

    /// The current theme values.
    @CopyOnWrite public var themes: BThemes {
        didSet {
            stylesheets.updateThemes(themes)
        }
    }

    /// Lazily-populated stylesheet cache, scoped to the current traits and themes.
    @EquatableIgnored @CopyOnWrite public private(set) var stylesheets: BStylesheets
}
