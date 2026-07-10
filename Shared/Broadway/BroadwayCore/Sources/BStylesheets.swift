//
//  BStylesheets.swift
//  BroadwayCore
//
//  Created by Kyle Van Essen on 3/3/26.
//

import Foundation

/// A keyed cache of ``BStylesheet`` instances, scoped to a specific
/// combination of traits and themes. Stylesheets are created lazily on
/// first access and cached for subsequent lookups with the same key.
public struct BStylesheets: Equatable, @unchecked Sendable {
    /// The current trait values (accessibility, size class, etc.).
    private var traits: BTraits

    /// The current theme values.
    private var themes: BThemes

    init(traits: BTraits, themes: BThemes) {
        self.traits = traits
        self.themes = themes
    }

    /// Keeps the resolver’s trait key in sync with ``BContext/traits``.
    /// `package` matches the monorepo `-package-name Broadway` set in Tuist (SE-0386).
    package mutating func updateTraits(_ newTraits: BTraits) {
        traits = newTraits
    }

    /// Keeps the resolver’s theme key in sync with ``BContext/themes``.
    package mutating func updateThemes(_ newThemes: BThemes) {
        themes = newThemes
    }

    // MARK: Lookup

    /// Returns the cached stylesheet of the given type, creating it lazily if needed.
    ///
    /// - Throws: ``StylesheetError/cyclicDependency(path:)`` if creation triggers
    ///   a dependency cycle, or ``StylesheetError/creationFailed(type:underlying:)``
    ///   if the stylesheet's initializer throws.
    public func get<Stylesheet: BStylesheet>(_: Stylesheet.Type) throws(StylesheetError) -> Stylesheet {
        let key = Key(
            stylesheet: .init(Stylesheet.self),
            traits: traits,
            themes: themes,
        )

        guard let value = cache[key], let value = value.base as? Stylesheet else {
            let id = TypeIdentifier(Stylesheet.self)

            let creating = _creating.wrappedValue._unsafeUnderlyingValue

            if let cycleStart = creating.firstIndex(of: id) {
                let path = creating[cycleStart...].map(\.debugDescription) + [id.debugDescription]
                throw .cyclicDependency(path: path)
            }

            _creating.wrappedValue._unsafeUnderlyingValue.append(id)
            defer { _creating.wrappedValue._unsafeUnderlyingValue.removeLast() }

            let context = SlicingContext(themes: themes, stylesheets: self)

            do {
                let new = try Stylesheet(context: context)
                _cache.wrappedValue._unsafeUnderlyingValue[key] = AnyEquatable(new)
                return new
            } catch let error as StylesheetError {
                throw error
            } catch {
                throw .creationFailed(type: id.debugDescription, underlying: error)
            }
        }

        return value
    }

    /// Explicitly sets a cached stylesheet value for the given type,
    /// replacing any previously cached instance for the current traits and themes.
    mutating func set<Stylesheet: BStylesheet>(_ newValue: Stylesheet) {
        let key = Key(stylesheet: .init(Stylesheet.self), traits: traits, themes: themes)
        cache[key] = AnyEquatable(newValue)
    }

    // MARK: Cache

    // TODO: Eventually we should clear this out on memory warnings for sheets not accessed within 10(?) min
    @EquatableIgnored @CopyOnWrite private var cache: [Key: AnyEquatable] = [:]

    @EquatableIgnored @CopyOnWrite private var creating: [TypeIdentifier] = []

    /// Cache key combining the stylesheet type with the traits and themes
    /// that were active at creation time.
    struct Key: Hashable {
        let stylesheet: TypeIdentifier
        let traits: BTraits
        let themes: BThemes
    }
}
